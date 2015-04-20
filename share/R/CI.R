library(drc)
CI.eff_ratio = function(x){ 
    return(x / (1-x));
}

CI.add_curve = function(m_1, m_2, dm_1, dm_2, d_1, d_2){
    step = 0.001
    additive.levels = sample(seq(0, 1,by=step), 50)
    additive.doses = sapply(additive.levels, function(level){ 
                            ratio = CI.eff_ratio(level); 
                            t1 =  d_1/(dm_1*(ratio^(1/m_1)))
                            t2 =  d_2/(dm_2*(ratio^(1/m_2)))
                            (d_1+d_2)/(t1 + t2)
    })
    data.add = data.frame(Dose=additive.doses, Effect=additive.levels)

    return(data.add)
}

CI.me_curve = function(m, dm, center_dose=NA){
    if (is.na(center_dose)) center_dose = dm
    doses.me = c(center_dose)

    for (i in seq(1,5,by=0.1)) {
        n = dm * i
        doses.me = c(doses.me, n)
        n = dm * 2^i
        doses.me = c(doses.me, n)
        n = dm * 4^i
        doses.me = c(doses.me, n)
        n = dm * 8^i
        doses.me = c(doses.me, n)
        n = dm * 16^i
        doses.me = c(doses.me, n)
        n = dm * 32^i
        doses.me = c(doses.me, n)
        n = dm / i
        doses.me = c(doses.me, n)
        n = dm / 2^i
        doses.me = c(doses.me, n)
        n = dm / 4^i
        doses.me = c(doses.me, n)
        n = dm / 8^i
        doses.me = c(doses.me, n)
        n = dm / 16^i
        doses.me = c(doses.me, n)
        n = dm / 32^i
        doses.me = c(doses.me, n)
    }

    doses.me = sort(doses.me)

    if (is.na(m)){
        data.me = data.frame(Dose=doses.me, Effect=rep(NA, length(doses.me)))
    }else{
        effect_ratios.me = sapply(doses.me, function(d){ (d / dm)^m });

        effects.me = sapply(effect_ratios.me, function(ratio){ ratio / (1+ratio) });

        data.me = data.frame(Dose=doses.me, Effect=effects.me)
    }

    return(data.me)
}

CI.least_squares.fix_log <- function(value){
    res = exp(value)/(1+exp(value))
    res[res>1] = 1
    return(res)
}

CI.predict_line <- function(modelfile, doses, least_squares=FALSE, invert=FALSE,level=0.95){
    data.drc = data.frame(Dose=doses);

    if (!is.null(modelfile)){
        model = rbbt.model.load(modelfile)
        if (least_squares){
            data.drc$Effect = predict(model, data.drc)
            data.drc$Effect.upr = predict(model, data.frame(Dose=data.drc$Dose),interval="confidence",level=level)[,'upr'];
            data.drc$Effect.lwr = predict(model, data.frame(Dose=data.drc$Dose),interval="confidence",level=level)[,'lwr'];

            data.drc$Effect = CI.least_squares.fix_log(data.drc$Effect)  
            data.drc$Effect.upr = CI.least_squares.fix_log(data.drc$Effect.upr)  
            data.drc$Effect.lwr = CI.least_squares.fix_log(data.drc$Effect.lwr)  

        }else{
            data.drc$Effect = predict(model, data.drc)
            data.drc$Effect.upr = predict(model, data.frame(Dose=data.drc$Dose),interval="confidence",level=level)[,'Upper'];
            data.drc$Effect.lwr = predict(model, data.frame(Dose=data.drc$Dose),interval="confidence",level=level)[,'Lower'];
        }
        if (invert){
            data.drc$Effect = 1 - data.drc$Effect
            data.drc$Effect.upr = 1 - data.drc$Effect.upr
            data.drc$Effect.lwr = 1 - data.drc$Effect.lwr
        }
    }else{
        data.drc$Effect = data.me$Effect
    }

    return(data.drc)
}

CI.plot_fit <- function(m, dm, data, data.me_points=NULL, modelfile=NULL, least_squares=FALSE, invert=FALSE){
    data.me = CI.me_curve(m, dm)
    max = max(data$Dose)
    min = min(data$Dose)
    data.me = subset(data.me, data.me$Effect <= 1)
    data.me = subset(data.me, data.me$Dose <= max)
    data.me = subset(data.me, data.me$Dose >= min)

    data.drc = CI.predict_line(modelfile, data.me$Dose, least_squares, invert)

    min.effect=min(c(0,data.me$Effect, data.drc$Effect, data.me_points$Effect))
    max.effect=max(c(1,data.me$Effect, data.drc$Effect, data.me_points$Effect))

    plot = ggplot(aes(x=Dose, y=Effect), data=data, ylim=c(min.effect,max.effect)) +
        scale_x_log10() + annotation_logticks() +
        geom_line(data=data.me, col='blue', cex=2) +
        geom_line(data=data.drc, col='blue', linetype='dashed',cex=2) +
        geom_point(cex=5) + 
        ylim(c(0,1)) +
        geom_point(data=data.me_points, col='blue',cex=5) 

    plot = plot + geom_ribbon(data=data.drc, aes(ymin=Effect.lwr, ymax=Effect.upr),col='blue',fill='blue',alpha=0.2, cex=0.1)

    return(plot)
}



CI.plot_combination <- function(blue_m, blue_dm, blue_dose, red_m, red_dm, red_dose, effect, blue_data, red_data, data.blue_me_points, data.red_me_points, blue.modelfile = NULL, red.modelfile=NULL, least_squares=FALSE, blue.invert=FALSE, red.invert=FALSE, fix_ratio=FALSE, more_doses = NULL, more_effects = NULL){

    data.blue_me = CI.me_curve(blue_m, blue_dm)

    data.red_me = CI.me_curve(red_m, red_dm)

    max = max(c(blue_data$Dose, red_data$Dose))
    min = min(c(blue_data$Dose, red_data$Dose))

    data.blue_me = subset(data.blue_me, data.blue_me$Effect <= 1)
    data.blue_me = subset(data.blue_me, data.blue_me$Dose <= max)
    data.blue_me = subset(data.blue_me, data.blue_me$Dose >= min)

    data.red_me = subset(data.red_me, data.red_me$Effect <= 1)
    data.red_me = subset(data.red_me, data.red_me$Dose <= max)
    data.red_me = subset(data.red_me, data.red_me$Dose >= min)

    #blue_model = rbbt.model.load(blue.modelfile);
    #data.blue_drc = data.frame(Dose=data.blue_me$Dose);
    #data.blue_drc$Effect = predict(blue_model, data.blue_drc);
    #if (least_squares){
    #    data.blue_drc$Effect = exp(data.blue_drc$Effect)/(1+exp(data.blue_drc$Effect))
    #    data.blue_drc$Effect[data.blue_drc$Effect > 1] = 1
    #}
    #
    #if (blue.invert){
    #    data.blue_drc$Effect = 1 - data.blue_drc$Effect
    #}


    #red_model = rbbt.model.load(red.modelfile);
    #data.red_drc = data.frame(Dose=data.red_me$Dose);
    #data.red_drc$Effect = predict(red_model, data.red_drc);

    #if (least_squares){
    #    data.red_drc$Effect = exp(data.red_drc$Effect)/(1+exp(data.red_drc$Effect))
    #    data.red_drc$Effect[data.red_drc$Effect > 1] = 1
    #}
    #
    #if (red.invert){
    #    data.red_drc$Effect = 1 - data.red_drc$Effect
    #}

    data.blue_drc = CI.predict_line(blue.modelfile, data.blue_me$Dose, least_squares, blue.invert)
    data.red_drc = CI.predict_line(red.modelfile, data.red_me$Dose, least_squares, red.invert)

    data.add = CI.add_curve(blue_m, red_m, blue_dm, red_dm, blue_dose, red_dose)

    data.add = subset(data.add, data.add$Effect <= 1)
    data.add = subset(data.add, data.add$Dose <= max)
    data.add = subset(data.add, data.add$Dose >= min)


    if (fix_ratio){
        blue_ratio = (blue_dose + red_dose)/blue_dose
        red_ratio = (blue_dose + red_dose)/red_dose
    }else{
        blue_ratio = red_ratio = 1
    }

    blue_data$Dose = blue_data$Dose * blue_ratio
    data.blue_me$Dose = data.blue_me$Dose * blue_ratio
    data.blue_drc$Dose = data.blue_drc$Dose * blue_ratio
    data.blue_me_points$Dose = data.blue_me_points$Dose * blue_ratio

    red_data$Dose = red_data$Dose * red_ratio
    data.red_me$Dose = data.red_me$Dose * red_ratio
    data.red_drc$Dose = data.red_drc$Dose * red_ratio
    data.red_me_points$Dose = data.red_me_points$Dose * red_ratio

    min.effect=min(c(0,effect, data.blue_me_points$Effect, data.blue_drc$Effect))
    max.effect=max(c(1,effect, data.blue_me_points$Effect, data.blue_drc$Effect))

    min.effect=min(c(min.effect, data.red_me_points$Effect, data.red_drc$Effect))
    max.effect=max(c(max.effect, data.red_me_points$Effect, data.red_drc$Effect))

    if (!is.null(more_effects)){
        min.effect=min(c(min.effect, more_effects))
        max.effect=max(c(max.effect, more_effects))
    }

    plot = ggplot(aes(x=as.numeric(Dose), y=as.numeric(Effect)), data=blue_data) + 
        ylim(min.effect, max.effect) +
        scale_x_log10() + annotation_logticks() +
        xlab("Combination dose") +
        ylab("Effect") +
        geom_point(data=blue_data, col='blue') +
        geom_point(data=red_data, col='red') +

        geom_line(data=data.blue_me, col='blue', cex=2) +
        geom_line(data=data.red_me, col='red', cex=2) +

        geom_line(data=data.blue_drc, linetype='dashed', col='blue', cex=1) +

        geom_line(data=data.red_drc, linetype='dashed', col='red', cex=1) +

        geom_line(data=data.add, col='black', cex=2) +

        geom_point(x=log10(blue_dose + red_dose), y=effect, col='black',cex=5) +


        geom_point(data=data.blue_me_points, col='blue',cex=5)  +
        geom_point(data=data.red_me_points, col='red',cex=5) 

    if (!is.null(more_effects)){
        len = length(more_doses)
        for (i in seq(1, len)){
            plot = plot + geom_point(x=log10(more_doses[i]), y=more_effects[i], col='black', cex=3)
        }
    }

    plot = plot + geom_ribbon(data=data.blue_drc, aes(ymin=Effect.lwr, ymax=Effect.upr),col='blue',fill='blue',alpha=0.2, cex=0.1)
    plot = plot + geom_ribbon(data=data.red_drc, aes(ymin=Effect.lwr, ymax=Effect.upr),col='red',fill='red',alpha=0.2, cex=0.1)

    return(plot)
}
