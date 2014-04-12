restricted.residual.mean <- function(out,x=0,tau=10,iid=0)
{ ## {{{ 
  if ((class(out)!='cox.aalen') & (class(out)!='aalen'))
      stop ("Must be output from cox.aalen or aalen function\n") 

if (class(out)=="cox.aalen") { ## {{{ 
time <- out$cum[,1]
cumhaz <- out$cum[,2]
beta <- out$gamma

if (is.matrix(x)!=TRUE) x <- matrix(x,nrow=1)
timetau <- c(time[time<tau],tau)
RR <- c( exp( x %*% beta) ) 
cumhaz<- matrix(1,nrow=nrow(x)) %*% t(matrix(cumhaz,ncol=(ncol(out$cum)-1)))
S0 <- exp(-cumhaz*RR)
S0t <- Cpred(cbind(time,t(S0)),timetau)[,-1,drop=FALSE]
Lam0t <- Cpred(cbind(time,t(cumhaz)),timetau)[,-1,drop=FALSE]
ll <- length(timetau)
ee <- apply(diff(timetau)*S0t[-ll,,drop=FALSE],2,sum)
deet <- apply(Lam0t[-ll,]*diff(timetau)*S0t[-ll,,drop=FALSE],2,sum)
RRDeet <- RR* deet

nn <- nrow(out$gamma.iid)
etiid <- c()
if (iid==1) {
   for (j in 1:nn) { 
      gamiid <- x %*% out$gamma.iid[j,] 
      gamiid <- RRDeet *  gamiid 
      Biidj<-Cpred(cbind(time,out$B.iid[[j]]),timetau)[,2]
      baseiid <- RR* 
      apply(diff(timetau)*S0t[-ll,,drop=FALSE]*Biidj[-ll],2,sum)
	   etiid <- rbind(etiid,c(gamiid+ baseiid))
   }
   variid <- t(etiid) %*% etiid 
   se  <- diag(variid)^.5
} else { var.mean <- se <- NULL }
} ## }}}

if (class(out)=="aalen")  ## {{{ 
{
time <- out$cum[,1]
cumhaz <- out$cum[,-1]

timetau <- c(time[time<tau],tau)
cumhaz<- as.matrix(x) %*% t(cumhaz)
S0 <- exp(-cumhaz)
S0t <- Cpred(cbind(time,t(S0)),timetau)[,-1,drop=FALSE]
Lam0t <- Cpred(cbind(time,t(cumhaz)),timetau)[,-1,drop=FALSE]
ll <- length(timetau)
ee <- apply(diff(timetau)*S0t[-ll,,drop=FALSE],2,sum)
deet <- apply(Lam0t[-ll,]*diff(timetau)*S0t[-ll,,drop=FALSE],2,sum)
RRDeet <- deet

nn <- length(out$B.iid)
etiid <- c()
if (iid==1) {
   for (j in 1:nn) { 
###	   gamiid <- x %*% out$gamma.iid[j,] 
###	   gamiid <- RRDeet *  gamiid 
	   Biidj<-Cpred(cbind(time,out$B.iid[[j]]),timetau)[,-1]
	   Biidj<- t(x %*% t(Biidj))
	   baseiid <- apply(diff(timetau)*S0t[-ll,,drop=FALSE]*Biidj[-ll,],2,sum)
	   etiid <- rbind(etiid,c(baseiid))
   }
   variid <- t(etiid) %*% etiid 
   se  <- diag(variid)^.5
} else { var.mean <- se <- NULL }
} ## }}}

out <- list(mean=ee,var.mean=variid,se=se,S0tau=S0t,timetau=timetau)
return(out)
} ## }}} 
