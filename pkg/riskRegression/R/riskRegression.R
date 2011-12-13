riskRegression <- function(formula,
                           data,
                           times,
                           link="relative",
                           cause,
                           resample.iid=1,
                           cens.model,
                           n.sim=0,
                           silent=1,
                           maxiter=50,
                           convLevel=6,
                           ...){
  # {{{ preliminaries
  interval=0.01
  weighted=0
  detail=0
  stopifnot(is.numeric(maxiter)&&maxiter>0&&(round(maxiter)==maxiter))
  stopifnot(silent %in% c(0,1))
  stopifnot(convLevel %in% 1:10)
  conv <- 10^{-convLevel}
  # trans=1 P_1=1-exp(- ( x' b(b)+ z' gam t^time.pow) ), 
  # trans=2 P_1=1-exp(-exp(x a(t)+ z` b )
  # trans=not done P_1=1-exp(-x a(t) exp(z` b )) is not good numerically
  # trans=3 P_1=exp(-exp(x a(t)+ z` b )
  ##   trans <- switch(link,"log"=
  trans <- switch(link,
                  "additive"=1, # 
                  "prop"=2,     # Proportional hazards (Cox, FG)
                  "logistic"=3, # Logistic absolute risks 
                  "relative"=4) # Relative absolute risks
  if (n.sim==0) sim <- 0 else sim <- 1
  nSimu <- n.sim

  # }}}
  # {{{ check if formula has the form Hist(time,event)~X1+X2+...
  
  formula.names <- try(all.names(formula),silent=TRUE)
  if (!(formula.names[1]=="~")
      ||
      (match("$",formula.names,nomatch=0)+match("[",formula.names,nomatch=0)>0)){
    stop("Invalid specification of formula. Perhaps forgotten right hand side?\nNote that any subsetting, ie data$var or data[,\"var\"], is invalid for this function.")
  }
  else
    if (!(formula.names[2] %in% c("Hist"))) stop("formula is NOT a proper event history formula,\nwhich must have a `Hist' object as response.")

  # }}}
  # {{{ read the data and the design
  call <- match.call()
  m <- match.call(expand = FALSE)
  if (match("subset",names(call),nomatch=FALSE))
    stop("Subsetting of data is not possible.")
  m <- m[match(c("","formula","data","subset","na.action"),names(m),nomatch = 0)]
  m[[1]]  <-  as.name("model.frame")
  if (missing(data)) stop("Argument 'data' is missing")
  formList <- readFormula(formula,specials=c("const","timevar","cluster"),specialArgumentNames=list("const"="power","timevar"="test"),unspecified="const")
  ##   formList <- readFormula(formula,specials=c("tv","cluster"),unspecified="const")
  m$formula <- formList$allVars
  theData <- eval(m, parent.frame())
  if ((nMiss <- (NROW(data)-NROW(theData)))>0)
    warning("Missing values: ",nMiss," lines have been removed from data before estimation.")
  if (NROW(theData) == 0) stop("No (non-missing) observations")
  # }}}
  # {{{ response
  response <- model.response(model.frame(formula=formList$Response,data=theData))
  responseType <- attr(response,"model")
  stopifnot(responseType %in% c("survival","competing.risks"))
  censType <- attr(response,"cens.type")
  stopifnot(censType %in% c("rightCensored","uncensored"))
  if (responseType!="survival" && !("event" %in% colnames(response)))
    warning("Only one cause of failure found in data.")
  Y <- as.vector(response[,"time"])
  time  <- numeric(length(Y))
  status <- as.vector(response[,"status"])
  states <- getStates(response)
  if (responseType=="survival")
    event <- status
  else
    event <-   as.numeric(getEvent(response))
  if (responseType=="competing.risks" && missing(cause)){
    cause <- 1
    message("Argument cause missing. Analyse cause: ",states[1])
  }
  else{
    if (responseType=="survival")
      cause <- 1
    else{
      if ((foundCause <- match(as.character(cause),states,nomatch=0))==0)
        stop(paste("Requested cause: ",cause," Available causes: ", states))
      else
        cause <- foundCause
    }
  }
  delta <- as.vector(response[,"status"])
  n <- length(Y)
  # }}}
  # {{{ intercept
  intercept <-  formList$Intercept
  # }}}
  # {{{ variables with time-varying coefficients

  X <- modelMatrix(formula=formList$timevar$formula,
                   data=theData,
                   intercept=intercept)
  if (NROW(X)==0)
    X <- cbind("Intercept"=rep(1,n))
  colnamesX <- colnames(X)
  dimX <- NCOL(X)
  factorLevelsX <- attr(X,"factorLevels")
  refLevelsX <- attr(X,"refLevels")
  default.timevar.test <- 0
  specArgsX <- formList$timevar$specialArguments
  given.timevar.test <- sapply(specArgsX,function(x){x$test})
  
  timevarTest <- sapply(colnamesX[colnamesX!="Intercept"],function(x){
    xx=strsplit(x,":")[[1]][[1]]
    if (found <- match(xx,names(given.timevar.test),nomatch=0))
      if (is.null(given.timevar.test[[found]]))
        given.timevar.test <- 0
      else
        as.numeric(given.timevar.test[found])
    else
      default.timevar.test
  })
  ## the intercept should not be tested, therefore we
  ## set the first element of timevarTest to zero
  timevar.test <- c(0,as.numeric(timevarTest))
  stopifnot(length(timevar.test)==dimX)
  if (!(all(timevar.test %in% 0:2)))
    stop("Time power tests only available for powers 0,1,2")

  # }}}
  # {{{ variables with time-constant coefficients
  npar <- is.null(formList$const$formula)
  if (npar){
    Z <- matrix(0,n,1)
    dimZ <- 1
    colnamesZ <- NULL
    fixed <- 0
    factorLevelsZ <- NULL
    refLevelsZ <- NULL
    timePower <- NULL
  }
  else{
    Z <- modelMatrix(formula=formList$const$formula,data=theData)
    dimZ <- NCOL(Z)
    fixed <- 1
    colnamesZ <- colnames(Z)
    factorLevelsZ <- attr(Z,"factorLevels")
    refLevelsZ <- attr(Z,"refLevels")
    specArgsZ <- formList$const$specialArguments
    default.timePower <- 0
    if (is.null(specArgsZ)){
      timePower <- rep(default.timePower,dimZ)
    }
    else{
      timePower <- sapply(colnames(Z),function(z){
        wo <- match(z,names(specArgsZ),nomatch=FALSE)
        if (!wo)
          wo <- match(strsplit(z,":.*")[[1]],names(specArgsZ),nomatch=FALSE)
        if (!wo){
          NULL
          warning("Cannot identify timepower for ",z)
        } else{
          specArgsZ[[wo]]$power
        }
      })
      stopifnot(length(timePower)==dimZ)
    }
    timePower <- as.numeric(timePower)
    names(timePower) <- colnames(Z)
    stopifnot(length(timePower)==dimZ)
    if (!(all(timePower %in% 0:2)))
      stop("Only powers of time in 0,1,2 can be multipled to constant covariates")
  }
  # }}}
  # {{{ cluster variable
  clusters <- modelMatrix(formula=formList$cluster$formula,data=theData)
  if(is.null(clusters)){
    clusters  <-  0:(NROW(X) - 1)
    antclust  <-  NROW(X)
  } else {
    clusters  <-  as.integer(factor(clusters))-1
    antclust  <-  length(unique(clusters))
  }
  # }}}
  # {{{ time points for timevarametric components
  if (missing(times)) {
    times <- sort(unique(Y[event==cause]));
    ## times <- times[-c(1:5)] 
  }
  else{
    times <- sort(unique(times))
  }
  ntimes <- length(times)
  # }}}
  # {{{ estimate ipcw
  iData <- data
  iData$itime <- response[,"time"]
  iData$istatus <- response[,"status"]
  iFormula <- as.formula(paste("Surv(itime,istatus)","~",as.character(formula)[[3]]))
  if (missing(cens.model)) cens.model <- "KM"
  imodel <- switch(cens.model,"KM"="marginal","cox"="cox","aalen"="aalen","uncensored"="none")
  Gcx <- subjectWeights(formula=iFormula,data=iData,method=cens.model,lag=1)$weights
  # }}}
  # {{{ prepare fitting
  if (resample.iid == 1){
    biid  <-  double(ntimes* antclust * dimX);
    gamiid <-  double(antclust *dimZ);
  } else {
    gamiid  <-  biid  <-  NULL;
  }
  # }}}
  # {{{ C does the hard work
  line <- ifelse(trans==1,1,0)
  # if line=1 then test "b(t) = gamma t"
  # if line=0 then test "b(t) = gamma "
  out <- .C("itfit",
            as.double(times),
            as.integer(ntimes),
            as.double(Y),
            as.integer(delta),
            as.integer(event),
            as.double(Gcx),
            as.double(X),
            as.integer(n),
            as.integer(dimX),
            as.integer(maxiter),
            double(dimX),
            score=double(ntimes*(dimX+1)),
            double(dimX*dimX),
            est=double(ntimes*(dimX+1)),
            var=double(ntimes*(dimX+1)),
            as.integer(sim),
            as.integer(nSimu),
            test=double(nSimu*3*dimX),
            testOBS=double(3*dimX),
            Ut=double(ntimes*(dimX+1)),
            simUt=double(ntimes*50*dimX),
            as.integer(weighted),
            gamma=double(dimZ),
            var.gamma=double(dimZ*dimZ),
            as.integer(fixed),
            as.double(Z),
            as.integer(dimZ),
            as.integer(trans),
            gamma2=double(dimX),
            as.integer(cause),
            as.integer(line),
            as.integer(detail),
            biid=as.double(biid),
            gamiid=as.double(gamiid),
            as.integer(resample.iid),
            as.double(timePower),
            as.integer(clusters),
            as.integer(antclust),
            as.double(timevar.test),
            silent=as.integer(silent),
            conv=as.double(conv),
            PACKAGE="riskRegression")
  # }}}
  # {{{ prepare the output

  if (fixed==1){
    timeConstantCoef <- out$gamma
    names(timeConstantCoef) <- colnamesZ
    timeConstantVar <- matrix(out$var.gamma,dimZ,dimZ,dimnames=list(colnamesZ,colnamesZ))
  }
  else{
  timeConstantCoef <- NULL
  timeConstantVar <- NULL
  }
  ## FIXME out$est should not include time
  timeVaryingCoef <- matrix(out$est,ntimes,dimX+1,dimnames=list(NULL,c("time",colnamesX)))
  timeVaryingVar <- matrix(out$var,ntimes,dimX+1,dimnames=list(NULL,c("time",colnamesX)))
  score <- matrix(out$score,ntimes,dimX+1,dimnames=list(NULL,c("time",colnamesX)))
  if (is.na(sum(score[,-1])))
    score <- NA
  else 
    if (sum(score[,-1])<0.00001)
      score <- sum(score[,-1])
  ##   time power test
  testedSlope <- out$gamma2
  names(testedSlope) <- colnamesX
  if (resample.iid==1)  {
    biid <- matrix(out$biid,ntimes,antclust*dimX)
    if (fixed==1) gamiid <- matrix(out$gamiid,antclust,dimZ) else gamiid <- NULL
    B.iid <- list()
    for (i in (0:(antclust-1))*dimX) {
      B.iid[[i/dimX+1]] <- matrix(biid[,i+(1:dimX)],ncol=dimX)
      colnames(B.iid[[i/dimX+1]]) <- colnamesX
    }
    if (fixed==1) colnames(gamiid) <- colnamesZ
  } else B.iid <- gamiid <- NULL
  
  if (sim==1) {
    simUt <- matrix(out$simUt,ntimes,50*dimX)
    UIt <- list()
    for (i in (0:49)*dimX) UIt[[i/dimX+1]] <- as.matrix(simUt[,i+(1:dimX)])
    Ut <- matrix(out$Ut,ntimes,dimX+1)
    colnames(Ut) <-  c("time",colnamesX)
    test <- matrix(out$test,nSimu,3*dimX)
    testOBS <- out$testOBS
    supUtOBS <- apply(abs(Ut[,-1,drop=FALSE]),2,max)
    # {{{ confidence bands
    
    percen<-function(x,per){
      n<-length(x)
      tag<-round(n*per)+1
      ud<-sort(x)[tag];
      return(ud)
    }
    unifCI <- do.call("cbind",lapply(1:dimX,function(i)percen(test[,i],0.95)))
    colnames(unifCI) <- colnamesX
    # }}}
    # {{{ Significance test
    posSig <- 1:dimX
    sTestSig <- testOBS[posSig]
    names(sTestSig) <- colnamesX
    
    pval<-function(simt,Otest)
      {
        simt<-sort(simt);
        p<-sum(Otest<simt)/length(simt);
        return(p)
      }
    
    pTestSig <- sapply(posSig,function(i){pval(test[,i],testOBS[i])})
    names(pTestSig) <- colnamesX
    timeVarSignifTest <- list(Z=sTestSig,pValue=pTestSig)
    # }}}
    # {{{ Kolmogoroff-Smirnoff test
    posKS <- (dimX+1):(2*dimX)
    sTestKS <- testOBS[posKS]
    names(sTestKS) <- colnamesX
    pTestKS <- sapply(posKS,function(i){pval(test[,i],testOBS[i])})
    names(pTestKS) <- colnamesX
    timeVarKolmSmirTest <- list(Z=sTestKS,pValue=pTestKS)
    # }}}
    # {{{ Kramer-von-Mises test
    posKvM <- (2*dimX+1):(3*dimX)
    sTestKvM <- testOBS[posKvM]
    names(sTestKvM) <- colnamesX
    pTestKvM <- sapply(posKvM,function(i){pval(test[,i],testOBS[i])})
    names(pTestKvM) <- colnamesX
    timeVarKramvMisTest <- list(Z=sTestKvM,pValue=pTestKvM)
    # }}}
  }
  # }}}
  # {{{ return results
  timeConstantEffects <- list(coef=timeConstantCoef,var=timeConstantVar)
  class(timeConstantEffects) <- "timeConstantEffects"
  timeVaryingEffects <- list(coef=timeVaryingCoef,
                             var=timeVaryingVar,
                             formula=formList$timevar$formula,
                             refLevels=refLevelsZ,
                             factorLevels=factorLevelsZ)
  class(timeVaryingEffects) <- "timeVaryingEffects"
  
  ud <- list(call=call,
             response=response,
             design=formList,
             link=link,
             time=times,
             timeConstantEffects=timeConstantEffects,
             timePower=timePower,
             timeVaryingEffects=timeVaryingEffects,
             score=score,
             censModel= cens.model,
             factorLevels=c(factorLevelsX,factorLevelsZ),
             refLevels=c(refLevelsX,refLevelsZ))

  if (resample.iid && sim==1)
    ud <- c(ud,list(resampleResults=list(conf.band=unifCI,
                      B.iid=B.iid,
                      gamma.iid=gamiid,
                      test.procBeqC=Ut,
                      sim.test.procBeqC=UIt)))
  if (sim==1)
    ud <- c(ud,list(timeVarSigTest=timeVarSignifTest,
                    timeVarKolmSmirTest=timeVarKolmSmirTest,
                    timeVarKramvMisTest=timeVarKramvMisTest))
  class(ud) <- "riskRegression"
  return(ud)

  # }}}
}
