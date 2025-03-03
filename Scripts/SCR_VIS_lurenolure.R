### SCR analysis for visual survey - lure vs no lure project
### Data was collected in 2015 where biologists walked transects in CP that either had traps with mice (lure) or no traps (no lure)
### The goal is to understand if encounter probability is different between these two scenarios
### In the case of an incipient or suppressed (low density) population, any way that we can maximize encounter rates (and thus detection probability) of brown treesnakes can be a useful resource for surveyors


rm(list = ls())

# Read functions to format data for SCR analysis
source("Data/PrepDataLure.R")

# Read in capture data and survey data and keep only relevant columns
caps <- read.csv("Data/CapturesLure.csv")[,c("EFFORTID","Date","PITTAG","SVL","TOTAL","WEIGHT","SEX","TRANSECT","LOCATION")]
survs <- read.csv("Data/SurveysLure.csv")[,c("EFFORTID","Date","TRANSECT","TYPE")]
# Restrict to 2-month period to meet assumptions of population closure
caps <- caps %>%
  filter(!grepl('Apr', Date))
survs <- survs %>%
  filter(!grepl('Apr', Date))

# Format captures and survey effort for traditional SCR analysis
dat <- PrepDat(caps,survs)

# Create trapping grid of Closed Population (CP) dimensions (5 ha, 50,000 m2)
locs <- secr::make.grid(nx = 13, ny = 27, spacex = 16, spacey = 8)
# Create matrix of survey locations
pts <- as.matrix(locs)
## Number of locations (lure/no lure points)
J <- nrow(pts)

## Define state-space of point process. (i.e., where animals live).
## "delta" just adds a fixed buffer to the outer extent of the traps.
## Don't need to estimate state-space since we know it (5 ha enclosed pop)
delta<- 11.874929
Xl<-min(locs[,1]) - delta
Xu<-max(locs[,1]) + delta
Yl<-min(locs[,2]) - delta
Yu<-max(locs[,2]) + delta
# Check area: 
A <- (Xu-Xl)*(Yu-Yl)

# Observations
y <- dat$snks
colnames(y) <- NULL
rownames(y) <- NULL
# Uniquely marked individuals
nind <- nrow(y)

# Matrix of effort where locations are active (surveyed = 1)/not active (not surveyed = 0) for all dates
act <- as.matrix(dat$act[,-1])
colnames(act) <- NULL
# Number of survey occasions
nocc <- ncol(act)

# Status of surveys (1 = not active, 2 = active but no lure, 3 = active and lure)
stat <- as.matrix(dat$stat[,-1])

## Data augmentation (i.e., add a number of uncaptured animals due to unknown abundance)
M <- 250
y <-abind(y,array(0,dim=c((M-nrow(y)),ncol(y),nocc)), along = 1)

## Starting values for activity centers (AC)
## set inits of AC to mean location of individuals and then to some random location within stat space for augmented individuals
set.seed(552020)
sst <- cbind(runif(M,Xl,Xu),runif(M,Yl,Yu))
sumy <- rowSums(y, dims=2)
for (i in 1:nind){
  for(k in 1:nocc){
    sst[i,1] <- mean(pts[sumy[i,]>0,1])
    sst[i,2] <- mean(pts[sumy[i,]>0,2])
  }
}

## Trick to skip estimating info for inactive transect points
# Get total survey occasions each transect location was surveyed
nActive <- apply(act, 1, sum)
# Create matrix of every transect location by which survey occasions it was open (so from 1 to 25 possible occasions, which occasions were active for this location)
ActiveOcc <- matrix(NA, J, max(nActive))
for(j in 1:J){
  ActiveOcc[j,1:nActive[j]] <- which(act[j,]==1)
}

## JAGS model
cat(file="Models/SCR0_DataAugLURE.txt","
model {

  for(l in 1:2){
    lam0[l]~dunif(0,1) ## Detection model with 1, 2 indicator for treatment (inactive occasions skipped)
  }
  sigma ~ dunif(0,50) ## Spatial decay parameter
  psi ~ dunif(0,1)

  for(i in 1:M){  ## for all augmented individuals
    z[i] ~ dbern(psi)
    s[i,1] ~ dunif(Xl,Xu)
    s[i,2] ~ dunif(Yl,Yu)
  
    for(j in 1:J) {  ## for all survey locations
      d2[i,j]<- pow(s[i,1]-pts[j,1],2) + pow(s[i,2]-pts[j,2],2)
        
      for(k in 1:nActive[j]){  ## for all active occasions
        p[i,j,ActiveOcc[j,k]] <- z[i]*lam0[STATUS[j,ActiveOcc[j,k]]]*exp(-(d2[i,j])/(2*sigma*sigma))
        y[i,j,ActiveOcc[j,k]] ~ dbern(p[i,j,ActiveOcc[j,k]])
      } # K
    } # J
  }  # M
  
  N <- sum(z[])               ## Abundance
  D <- N/A                    ## Density
  delta <- lam0[2] - lam0[1]  ## Difference between lure and no lure enc. rate
  
}")

# MCMC settings
nc <- 3; nAdapt=1000; nb <- 1; ni <- 2000+nb; nt <- 1

# data and constants
jags.data <- list (y=y, pts=pts, M=M, J=J, Xl=Xl, Xu=Xu, Yl=Yl, Yu=Yu, A=A, STATUS=stat-1, nActive=nActive, ActiveOcc=ActiveOcc)
# do stat-1 since the only functional categories are 2 and 3... inactive state becomes 0 this way.

inits <- function(){
  list (sigma=runif(1,40,50), z=c(rep(1,nind),rep(0,M-nind)), s=sst, psi=runif(1), lam0=runif(2,0.05,0.07))
}

parameters <- c("sigma","psi","N","D","lam0","delta")

## WORKAROUND: https://github.com/rstudio/rstudio/issues/6692
## Revert to 'sequential' setup of PSOCK cluster in RStudio Console on macOS and R 4.0.0
if (Sys.getenv("RSTUDIO") == "1" && !nzchar(Sys.getenv("RSTUDIO_TERM")) && 
    Sys.info()["sysname"] == "Darwin" && getRversion() >= "4.0.0") {
  parallel:::setDefaultClusterOptions(setup_strategy = "sequential")
}
out <- jagsUI("Models/SCR0_DataAugLURE.txt", data=jags.data, inits=inits, parallel=TRUE,
            n.chains=nc, n.burnin=nb,n.adapt=nAdapt, n.iter=ni, parameters.to.save=parameters)

save(out, file="Results/SCRVISlurenolure.RData")

