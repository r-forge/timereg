\name{plotEffects}
\alias{plotEffects}
%- Also NEED an '\alias' for EACH other topic documented here.
\title{
  Plotting time-varying effects from a risk regression model.
}
\description{
  Plot time-varying effects from a risk regression model.  
}
\usage{
plotEffects(x, formula, level, refLine = TRUE, confint = 0.95, xlim, ylim, xlab = "Time", ylab = "Cumulative coefficient", col, lty, lwd, add = FALSE, legend, axes = TRUE, ...)
}
%- maybe also 'usage' for other objects documented here.
\arguments{
  \item{x}{
    Fitted object obtained with one of \code{ARR}, \code{LRR}, \code{riskRegression}.
  }
  \item{formula}{
    A formula to specify the variable(s) whose regression coefficients should be plotted.
  }
  \item{level}{
    For categorical variables the level (group) whose contrast to the
    reference level (group) should be plotted.
}
\item{refLine}{
  Logical. If \code{TRUE} then add a horizontal line at zero.
  }
  \item{confint}{
    Logical. If \code{TRUE} then add confidence limits.
    % Can be
    % controlled using smart arguments. See examples
}
  \item{xlim}{
    See \code{plot}
  }
  \item{ylim}{
    See \code{plot}
}
  \item{xlab}{
    See \code{plot}
}
  \item{ylab}{
    See \code{plot}
}
  \item{col}{
    A vector of colors for the regression coefficients.
  }
  \item{lty}{
    A vector of line types for the regression coefficients.
  }
  \item{lwd}{
        A vector of line thicknesses for the regression coefficients.
}
  \item{add}{
    Logical. If \code{TRUE} then add lines to an existing plot.
  }
  \item{legend}{
    Logical. If \code{TRUE} then add a legend. Can be controlled using smart arguments. See examples.
  }
  \item{axes}{
    Logical. If \code{FALSE} then do not draw axes.
  }
  \item{\dots}{
    Used for transclusion of smart arguments for \code{plot},
    \code{axis}. See function
    \code{\link{SmartControl}} from prodlim.
  }
}
% \details{
%%  ~~ If necessary, more details than the description above ~~
% }
% \value{
%%  ~Describe the value returned
%%  If it is a LIST, use
%%  \item{comp1 }{Description of 'comp1'}
%%  \item{comp2 }{Description of 'comp2'}
%% ...
% }
% \references{
%% ~put references to the literature/web site here ~
% }
\author{
  Thomas H. Scheike
  \email{ts@biostat.ku.dk}
  
  Thomas A. Gerds
  \email{tag@biostat.ku.dk} 
}
% \note{
%%  ~~further notes~~
% }

%% ~Make other sections like Warning with \section{Warning }{....} ~

% \seealso{
%% ~~objects to See Also as \code{\link{help}}, ~~~
% }
\examples{

data(Melanoma)

fit.tarr <- ARR(Hist(time,status)~strata(sex),data=Melanoma,cause=1)
plotEffects(fit.tarr)

fit.tarr <- ARR(Hist(time,status)~strata(sex)+strata(invasion),data=Melanoma,cause=1,times=seq(800,3000,20))
plotEffects(fit.tarr,formula=~sex)
plotEffects(fit.tarr,formula=~invasion)
plotEffects(fit.tarr,formula=~invasion,level="invasion:level.1")

## legend arguments are transcluded:
plotEffects(fit.tarr,formula=~invasion,legend.bty="b",legend.cex=1)

## and other smart arguments too:
plotEffects(fit.tarr,
	    formula=~invasion,
	    legend.bty="b",
            axis2.las=2,
	    legend.cex=1)

}
% Add one or more standard keywords, see file 'KEYWORDS' in the
% R documentation directory.
\keyword{survival }