## Note: this file modifies ACT-R to respect category as hard constraint

## Standard error:
se <- function(x, na.rm = TRUE){
  if(na.rm) y <- x[!is.na(x)] # remove the missing values, if any
  sqrt(var(as.vector(y))/length(y))
}


## The act-r random logistic function. Note that this 

actr.logis <- function(trials,alpha,beta) {
    r1 <- runif(trials,0,1);
    r2 <- runif(trials,0,1);
    return(alpha + beta * log(r1/(1-r2)))
}


## Base level activation computation.  Assumes a matrix "history" that has
## a column vector for each past retrieval moment, where the column vector
## identifies the winning item for each trial.

compute.base.levels <- function(moment) {
  if (d == FALSE) {
    base.levels <- matrix(0,nrow=num.items,ncol=trials);
    return(base.levels);
  }
  
  ## time since last retrieval for each retrieval (converted from milliseconds)
  tj <- (moment/1000) - (moments/1000);
  
  ## just pay attention to past, not future
  past <- history[, tj > 0];
  num.past.retrievals <- sum(tj > 0);
  
  ## the decay function
  tjd <- tj ^ -d;
  decay <- matrix(tjd[tj > 0], nrow=trials, ncol=num.past.retrievals,byrow=TRUE);
  
  ## compute base level activation for each item (for each trial)
  base.levels <- matrix(nrow=num.items, ncol=trials);
  for (c in 1:num.items) {
    retrievals <- past == c;                  # boolean matrix
    activations <- retrievals * decay;
    b <- log(rowSums(activations,na.rm=TRUE));     # sum over all j retrievals
    b[is.infinite(b)] <- 0;                      # don't propagate through infinite values
    base.levels[c,] <- b;
  }
  return(base.levels);
}



## Retrieval time computation: computes distribution of retrieval times for all
## items given a retrieval cue feature vector and a moment in time to do the
## retrieval.  Updates the history matrix with the winning items for this
## retrieval moment over all the trials.

retrieve <- function(cue.names, retrieval.cues, retrieval.moment) {
    num.cues <- length(retrieval.cues) - length(retrieval.cues[retrieval.cues=="NULL"]);

    ## compute base level activations
    base.levels <- compute.base.levels(retrieval.moment);

    ## compute the match between items and retrieval cues (a boolean matrix)
    cues <- matrix(data=as.matrix(retrieval.cues),nrow=num.items, ncol=num.features,byrow=TRUE);
    is.nil <- item.features == "nil";    
    is.variable.cue <- cues == "VAR";

    match <- (item.features == cues);
    match.inc.var <- match | (is.variable.cue & !is.nil);

    ## checks which items exist at this moment
    exists <- matrix(creation.moment < retrieval.moment,nrow=num.items,ncol=num.features);

    ## checks which items match category cue
    item.category <- item.features[,cue.names=="cat"];
    cue.category <- cues[,cue.names=="cat"];
    matches.category <- matrix((item.category == cue.category), nrow=num.items,ncol=trials);

    ## compute fan for each feature: number of existing items matching each feature
    fan <- colSums(match.inc.var & exists) +  VAR.fan * is.variable.cue[1,];
    strength <- mas - log(fan);                       # fan equation


    ## compute source activation available for each cue (source spread over
    ## cues) and multiply by the fan (S * W in act-r equation).

    ## THIS IS NEW: We make VAR cues provide half the activation of other
    ## cues (because they only provide only half of the {feature,value} pair)
    cue.weights <- 1 - as.integer(is.variable.cue[1,])/2
    cue.weights <- cue.weights/sum(cue.weights[retrieval.cues!="NULL"])

    W <- G * cue.weights;    

#    W <- G/num.cues;
    
    sw <- matrix(strength * W, nrow=num.items, ncol=num.features,byrow=TRUE);
    
    ## compute extra activation for each item; sum must ignore NA's because
    ## those correspond to features that are not retrieval cues.
    extra <- rowSums(match.inc.var * sw, na.rm=TRUE);    
    
    ## compute mismatch penalty
    is.retrieval.cue <- (cues != "NULL") & (cues != "VAR");

    if (var.mismatch.penalty) {
      mismatch <- (!match & is.retrieval.cue)  | (is.variable.cue & is.nil);
    } else {
      mismatch <- (!match & is.retrieval.cue);
    };

    ## mismatch <- (!match & is.retrieval.cue)  | (is.variable.cue & is.nil);
    penalty <- rowSums(mismatch * match.penalty);
    
    ## compute activation boost/penalty
    activation.adjustment <- extra + penalty;
    boost <- matrix(activation.adjustment, ncol=trials, nrow=num.items); 

    ## add to base-level
    if (modulate.by.distinct) {
      ## compute how distinctive each item is (proportional to base-level activation)
      d.boost <- distinctiveness + base.levels;   
      activation <- base.levels + boost * d.boost;
    } else {
      activation <- base.levels + boost;
    };
    
    noise <- matrix(rlogis(trials*num.items,0,ans), ncol=trials,nrow=num.items);
    noisy.activation <- activation + noise;

    ## make items that don't exist yet, or that don't match category cues,  have activation of -999
    exists <- matrix(creation.moment <  retrieval.moment,nrow=num.items,ncol=trials);
    exists.matches.cat <- exists & matches.category;
    exists.but.doesnt.match.cat <- exists & !matches.category;

    doesnt.exist.penalty <- 9999* !exists;
    doesnt.match.cat.penalty <- 9999* !matches.category;

    final.activation  <- noisy.activation*exists + -999*!exists +
               cat.penalty*!matches.category;
    activation.mean <- rowMeans(final.activation);
    if(use.standard.error) {
      activation.sd <- apply(final.activation, 1, se, na.rm=TRUE);} else {
        activation.sd <- apply(final.activation, 1, sd, na.rm=TRUE);}


    ## compute latency given the noisy activation, and mean and sd over all the
    ## monte carlo trials. Make non-existent items have a retrieval time of 9999.
    retrieval.latency <- (F * exp(-noisy.activation))*1000;
    final.latency  <- retrieval.latency*exists + doesnt.exist.penalty + doesnt.match.cat.penalty;

    latency.mean <- rowMeans(final.latency);
    if(use.standard.error){
      latency.sd <- apply(final.latency, 1, se, na.rm=TRUE);} else {
        latency.sd <- apply(final.latency, 1, sd, na.rm=TRUE);}

    ## find winning item for each trial, and count # of times each item won
    winner <- apply(final.latency, 2, which.min);
    winner.latency <- apply(final.latency, 2, min);    
    counts <- rep(0,num.items);
    
    item.winners <- NULL;
    for (c in 1:num.items) {
	counts[c] <- sum(winner == c)
        item.winners <- cbind(item.winners, winner==c);
    };

    retrieval.prob.lower <- rep(NA,num.items);
    retrieval.prob.upper <- rep(NA,num.items);

    if (!(is.na(num.experimental.items) | is.na(num.experimental.subjects))) {
      
      ## create a vector of subject IDs and experiment IDs
      subjects <- rep(1:trials,each=num.experimental.items,length.out=trials);
      subject.means <- aggregate(item.winners, by=list(subjects), FUN=mean);
      
      ## now create a vector of experiment IDs
      experiments <- rep(1:trials, each=num.experimental.subjects,length.out=length(subject.means[,1]));
      experiment.means <- aggregate(subject.means, by=list(experiments), FUN=mean);
      
      retrieval.prob.lower <- apply(experiment.means[,3:(2+num.items)], MARGIN=2,
                                FUN=function(x) {
#                                  return(quantile(x,probs=c(0.025)));
                                  return(quantile(x,probs=c(0.1586)));                                  
                                });
      
      retrieval.prob.upper <- apply(experiment.means[,3:(2+num.items)], MARGIN=2,
                                FUN=function(x) {
#                                  return(quantile(x,probs=c(0.975)));
                                  return(quantile(x,probs=c(0.8413)));                                  
                                });
    }

    
    ## probability of retrieval
    retrieval.prob <- counts / trials;
    winner.latency.mean <- mean(winner.latency);
    if(use.standard.error){
      winner.latency.sd <- se(winner.latency);} else {
        winner.latency.sd <- sd(winner.latency);}

    summary <-  data.frame(item=c(item.name, "WINNER"),
                           retrieval.prob=c(retrieval.prob,1.0),
                           retrieval.prob.lower=c(retrieval.prob.lower,NA),
                           retrieval.prob.upper=c(retrieval.prob.upper,NA),                           
                           latency.mean=c(latency.mean,winner.latency.mean),
                           latency.sd=c(latency.sd,winner.latency.sd),
                           activation.mean=c(activation.mean,NA),
                           activation.sd=c(activation.sd,NA));
    
    if(use.standard.error) colnames(summary)[c(6,8)] <- c("latency.se", "activation.se")

    return(list(summary=summary, winner=winner,latency.mean=latency.mean,final.latency=final.latency));    
}




## plot the activation profiles given a set of retrieval moments and a retrieval history

plot.activation.profiles <- function(moments, history, min.time, max.time,increment=10,
                                     creation.moments,item.names=item.name) {
    time.span <- seq(min.time,max.time,increment);
    base.activations <- matrix(nrow=num.items, ncol=length(time.span));

#    print("Computing complete history of activation values at times....");

    ##  First compute the history of activation values at each time point
    j <- 1;
    for (t in time.span) {
#	if (round(t/100)==t/100) {print(t)};
  	base.levels <- compute.base.levels(t);
	
	## make items that don't exist yet have activation of NA
	exists <- matrix(creation.moment <  t, ncol=trials, nrow=num.items);    
	activation  <- base.levels*exists + 0*!exists;
        activation[activation==0] <- NA;

	## take mean activation over all the monte carlo trials
	base.activations[,j] <- rowMeans(activation);
        j <- j + 1;
    }

    maxb <- max(base.activations,na.rm=TRUE);
    minb <- min(base.activations,na.rm=TRUE);

    plot(base.activations[1,] ~ time.span,
               type="l", lwd=1.5,col=clrs[1],
               main=paste(title.prefix, "Mean activation of items over time (", trials," runs)",sep=""),
               sub="Green bars indicate initial encoding points, red bars indicate retrieval points",
               ylab="Activation", xlab="Time",
               ylim=c(minb-0.5, maxb+0.5));

    lines(x=c(min(time.span),max(time.span)), y=c(0,0),lty=3);
    
    for (c in 1:num.items) {
      lines(base.activations[c,] ~ time.span,
            type="l",lwd=1.5,col=clrs[c]);  
    };
    
    ## add markers for the creation and retrieval moments at the bottom
    for (m in creation.moments) {
      lines(x=c(m,m), y=c(minb -0.1, minb-0.5),lend=2,lwd=2,col="darkgreen");
    }

    for (m in setdiff(moments, creation.moments)) {
      lines(x=c(m,m), y=c(minb -0.1, minb-0.5),lend=2,lwd=4,col="red");
    }

    
    ## add a legend
    width <- max.time - min.time;
    height <- maxb;
    legend(0.8*width+min.time, height+0.5, item.name, lty=1,lwd=1.5,bty="n",
	   col = clrs[1:num.items]); 
  }


