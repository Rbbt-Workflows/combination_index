rbbt.require('drc')
rbbt.require('ggplot2')


CI.eff_ratio = function(x){ 
    return(x / (1-x));
}


CI.misc.seq <- function(){
    res = seq(0, 0.1, length.out=50)
    res = c(res, seq(0.1, 0.9, length.out=50))
    res = c(res, seq(0.9, 1, length.out=50))

    return(res)
}

CI.misc.log_seq <- function(center.point){

    res = c(center.point)
    for (i in seq(1,5,by=0.5)) {
        n = center.point * i
        res = c(res, n)
        n = center.point * 2^i
        res = c(res, n)
        n = center.point * 4^i
        res = c(res, n)
        n = center.point * 8^i
        res = c(res, n)
        n = center.point * 16^i
        res = c(res, n)
        n = center.point * 32^i
        res = c(res, n)
        n = center.point * 64^i
        res = c(res, n)
        n = center.point / i
        res = c(res, n)
        n = center.point / 2^i
        res = c(res, n)
        n = center.point / 4^i
        res = c(res, n)
        n = center.point / 8^i
        res = c(res, n)
        n = center.point / 16^i
        res = c(res, n)
        n = center.point / 32^i
        res = c(res, n)
        n = center.point / 64^i
        res = c(res, n)
    }

    for (i in seq(0,100, by=1)) {
        res = c(res, i)
    }

    return(sort(res))
}

CI.add_curve = function(m_1, m_2, dm_1, dm_2, d_1, d_2){
    additive.levels = CI.misc.seq()
    additive.doses = sapply(additive.levels, function(level){ 
                            ratio = CI.eff_ratio(level); 
                            t1 =  d_1/(dm_1*(ratio^(1/m_1)))
                            t2 =  d_2/(dm_2*(ratio^(1/m_2)))
                            (d_1+d_2)/(t1 + t2)
    })

    data.add = data.frame(Dose=additive.doses, Response=additive.levels)

    return(data.add)
}

CI.add_curve.bliss = function(m_1, m_2, dm_1, dm_2, d_1, d_2){
    additive.levels = CI.misc.seq()
    additive.doses = sapply(additive.levels, function(level){ 
                            ratio = CI.eff_ratio(level); 
                            t1 =  d_1/(dm_1*(ratio^(1/m_1)))
                            t2 =  d_2/(dm_2*(ratio^(1/m_2)))
                            (d_1+d_2)/(t1 + t2)
    })

    data.add = data.frame(Dose=additive.doses, Response=additive.levels)

    return(data.add)
}

CI.me_curve = function(m, dm, center_dose=NA){
    if (is.na(center_dose)) center_dose = dm
    doses.me = c(CI.misc.log_seq(center_dose), CI.misc.seq())

    if (is.null(m) || is.na(m)){
        data.me = data.frame(Dose=doses.me, Response=rep(NA, length(doses.me)))
    }else{
        response_ratios.me = sapply(doses.me, function(d){ (d / dm)^m });

        responses.me = sapply(response_ratios.me, function(ratio){ ratio / (1+ratio) });

        data.me = data.frame(Dose=doses.me, Response=responses.me)
    }

    return(data.me)
}

CI.least_squares.fix_log <- function(value){
    res = exp(value)/(1+exp(value))
    res[res>1] = 1
    return(res)
}

CI.predict_line <- function(modelfile, doses, least_squares=FALSE, invert=FALSE,level=0.90){
    data.drc = data.frame(Dose=doses);

    if (!is.null(modelfile)){
        model = rbbt.model.load(modelfile)
        if (least_squares){
            data.drc$Response = predict(model, data.drc)
            data.drc$Response = CI.least_squares.fix_log(data.drc$Response)  

            tryCatch({
                data.drc$Response.upr = predict(model, data.frame(Dose=data.drc$Dose), interval="confidence", level=level)[,'upr'];
                data.drc$Response.lwr = predict(model, data.frame(Dose=data.drc$Dose), interval="confidence", level=level)[,'lwr'];
                data.drc$Response.upr = CI.least_squares.fix_log(data.drc$Response.upr)   
                data.drc$Response.lwr = CI.least_squares.fix_log(data.drc$Response.lwr)   
            })

        }else{
            data.drc$Response = predict(model, data.drc)
            tryCatch({
                data.drc$Response.upr = predict(model, data.frame(Dose=data.drc$Dose), interval="confidence", level=level)[,'Upper'];
                data.drc$Response.lwr = predict(model, data.frame(Dose=data.drc$Dose), interval="confidence", level=level)[,'Lower'];
            })
        }
        if (invert){
            data.drc$Response = 1 - data.drc$Response
            tryCatch({
                data.drc$Response.upr = 1 - data.drc$Response.upr
                data.drc$Response.lwr = 1 - data.drc$Response.lwr
            })
        }
    }else{
        return(NULL)
    }

    return(data.drc)
}

CI.subset_data <- function(data, min, max){
    data = subset(data, data$Response <= 1)
    data = subset(data, data$Dose <= max)
    data = subset(data, data$Dose >= min)
    return(data)
}

#{{{ PLOTS }}}#

CI.plot_fit <- function(m, dm, data, data.me_points=NULL, modelfile=NULL, least_squares=FALSE, invert=FALSE, random.samples=NULL){
    data.me = CI.me_curve(m, dm)
    max = max(data$Dose)
    min = min(data$Dose)
    data.me = subset(data.me, data.me$Response <= 1)
    data.me = subset(data.me, data.me$Dose <= max)
    data.me = subset(data.me, data.me$Dose >= min)

    data.drc = CI.predict_line(modelfile, data.me$Dose, least_squares, invert)
    
    if (is.null(data.drc)){
        data.drc = data.me
    }

    min.response=min(c(0,data.me$Response, data.drc$Response, data.me_points$Response))
    max.response=max(c(1,data.me$Response, data.drc$Response, data.me_points$Response))

    min.dose = min(data.me_points$Dose)
    max.dose = max(data.me_points$Dose)

    if (least_squares){
        plot = ggplot(aes(x=Dose, y=log(Response/(1-Response))), data=data) #+ xlim(log(c(min.dose, max.dose))) + ylim(c(1,-1))
    }else{
        plot = ggplot(aes(x=Dose, y=Response), data=data) + ylim(c(min.response,max.response)) #+ xlim(log(c(min.dose, max.dose)))
    }


    if(sum(!is.nan(data.drc$Response.upr)) > 0 && ! least_squares){
        plot = plot + geom_ribbon(data=data.drc, aes(ymin=Response.lwr, ymax=Response.upr),col='blue',fill='blue',alpha=0.2, cex=0.1)
    }

    if (!is.null(random.samples) && length(random.samples)>0){
        for (i in seq(0,length(random.samples)/2)){
            m.s = random.samples[2*i+1]
            dm.s = random.samples[2*i+2]
            data.me.s = CI.me_curve(m.s, dm.s)
            data.me.s = CI.subset_data(data.me.s, min, max)
            plot = plot + geom_line(data=data.me.s, col='cyan', cex=2, linetype='solid', alpha=0.2)
        }
    }

    plot = plot +
           scale_x_log10() + annotation_logticks(side='b') +
           geom_line(data=data.me, col='blue', cex=2) +
           geom_line(data=data.drc, col='blue', linetype='dotted',cex=2) +
           geom_point(cex=5) + 
           geom_point(data=data.me_points, col='blue',cex=7, shape=18) +
           geom_point(data=data.me_points, col='white',cex=4, shape=18) 


    return(plot)
}



CI.plot_combination <- function(blue_m, blue_dm, blue_dose, red_m, red_dm, red_dose, response, blue_data, red_data, data.blue_me_points, data.red_me_points, blue.modelfile = NULL, red.modelfile=NULL, least_squares=FALSE, blue.invert=FALSE, red.invert=FALSE, fix_ratio=FALSE, more_doses = NULL, more_responses = NULL, blue.random.samples=NULL, red.random.samples=NULL, blue.fit_dose = NULL, red.fit_dose = NULL){

    data.blue_me = CI.me_curve(blue_m, blue_dm)

    data.red_me = CI.me_curve(red_m, red_dm)

    max = max(c(blue_data$Dose, red_data$Dose))
    min = min(c(blue_data$Dose, red_data$Dose))

    data.blue_me = subset(data.blue_me, data.blue_me$Response <= 1)
    data.blue_me = subset(data.blue_me, data.blue_me$Dose <= max)
    data.blue_me = subset(data.blue_me, data.blue_me$Dose >= min)

    data.red_me = subset(data.red_me, data.red_me$Response <= 1)
    data.red_me = subset(data.red_me, data.red_me$Dose <= max)
    data.red_me = subset(data.red_me, data.red_me$Dose >= min)

    if (fix_ratio){
        blue_ratio = (blue_dose + red_dose)/blue_dose
        red_ratio = (blue_dose + red_dose)/red_dose
    }else{
        blue_ratio = red_ratio = 1
    }


    data.add = CI.add_curve(blue_m, red_m, blue_dm, red_dm, blue_dose, red_dose)

    data.blue_drc = CI.predict_line(blue.modelfile, data.add$Dose/blue_ratio, least_squares, blue.invert)
    data.red_drc = CI.predict_line(red.modelfile, data.add$Dose/red_ratio, least_squares, red.invert)

    if (is.null(data.blue_drc)){
        data.blue_drc = data.blue_me
    }

    if (is.null(data.red_drc)){
        data.red_drc = data.red_me
    }

    blue_data$Dose = blue_data$Dose * blue_ratio
    data.blue_me$Dose = data.blue_me$Dose * blue_ratio
    data.blue_drc$Dose = data.blue_drc$Dose * blue_ratio
    data.blue_me_points$Dose = data.blue_me_points$Dose * blue_ratio

    red_data$Dose = red_data$Dose * red_ratio
    data.red_me$Dose = data.red_me$Dose * red_ratio
    data.red_drc$Dose = data.red_drc$Dose * red_ratio
    data.red_me_points$Dose = data.red_me_points$Dose * red_ratio

    min.response=min(c(0,response, data.blue_me_points$Response, data.blue_drc$Response))
    max.response=max(c(1,response, data.blue_me_points$Response, data.blue_drc$Response))

    min.response=min(c(min.response, data.red_me_points$Response, data.red_drc$Response))
    max.response=max(c(max.response, data.red_me_points$Response, data.red_drc$Response))

    if (!is.null(more_responses)){
        min.response=min(c(min.response, more_responses))
        max.response=max(c(max.response, more_responses))
    }

    max.response = min(c(1, max.response))
    min.response = max(c(0, min.response))

    all.doses = c(data.blue_me$Dose, data.red_me$Dose, more_doses)
    min.dose = min(all.doses)
    max.dose = max(all.doses)

    data.blue_drc = CI.subset_data(data.blue_drc, min.dose, max.dose)
    data.red_drc = CI.subset_data(data.red_drc, min.dose, max.dose)

    data.blue_me = CI.subset_data(data.blue_me, min.dose, max.dose)
    data.red_me = CI.subset_data(data.red_me, min.dose, max.dose)

    data.add = CI.subset_data(data.add, min.dose, max.dose)

    plot = ggplot(aes(x=as.numeric(Dose), y=as.numeric(Response)), data=blue_data) 

    if (!is.null(more_responses)){
        len = min(c(length(more_doses), length(more_responses)))
        md=more_doses[1:len]
        me=more_responses[1:len]
        plot = plot + geom_smooth(aes(x=Dose, y=Response), data=data.frame(Dose=md, Response=me), linetype='dashed', col='black', level=0.95, se=FALSE)
    }
    
    if (!is.null(blue.random.samples) && !is.null(red.random.samples)){
        max = min(length(blue.random.samples), length(red.random.samples))
        for (i in seq(0,max/2)){
            m.blue.s = blue.random.samples[2*i+1]
            dm.blue.s = blue.random.samples[2*i+2]
            m.red.s = red.random.samples[2*i+1]
            dm.red.s = red.random.samples[2*i+2]
            data.add.s = CI.add_curve(m.blue.s, m.red.s, dm.blue.s, dm.red.s, blue_dose, red_dose)
            data.add.s = CI.subset_data(data.add.s, min.dose, max.dose)
            plot = plot + geom_line(data=data.add.s, col='cyan', cex=2, linetype='solid', alpha=0.2)
        }
    }

    plot = plot +
        xlim(min.dose, max.dose) +
        ylim(min.response, max.response) +
        scale_x_log10() + 
        annotation_logticks(side='b') +
        xlab("Dose") +
        ylab("Response") +
        geom_point(data=blue_data, col='blue',cex=3,alpha=0.8) +
        geom_point(data=red_data, col='red',cex=3,alpha=0.8) +

        geom_line(data=data.blue_me, col='blue', cex=2,alpha=0.8) +
        geom_line(data=data.red_me, col='red', cex=2,alpha=0.8) +

        geom_line(data=data.blue_drc, linetype='dashed', col='blue', cex=1,alpha=0.8) +

        geom_line(data=data.red_drc, linetype='dashed', col='red', cex=1,alpha=0.8) +

        geom_line(data=data.add, col='black', cex=2,alpha=0.8) +

        geom_point(x=log10(blue_dose + red_dose), y=response, col='black',cex=5,alpha=0.8) +

        geom_point(data=data.blue_me_points, col='blue', shape = 18, cex=7)  +
        geom_point(data=data.blue_me_points, col='white', shape = 18, cex=4)  +
        geom_point(data=data.red_me_points, col='red', shape = 18, cex=7)  +
        geom_point(data=data.red_me_points, col='white', shape = 18, cex=4) 

    if (!is.null(more_responses)){
        for (i in seq(1, len)){
            plot = plot + geom_point(x=log10(more_doses[i]), y=more_responses[i], col='black', cex=2, alpha=0.4)
        }
    }

    if (!is.null(blue.fit_dose)){
        plot = plot + geom_vline(x=blue.fit_dose*blue_ratio, col='blue', cex=1, linetype='dotted')
        plot = plot + geom_vline(x=red.fit_dose*red_ratio, col='red', cex=1, linetype='dotted')
    }

    return(plot)
}

CI.plot_combination.bliss <- function(blue_dose, red_dose, response, blue_data, red_data, bliss_data, additive_data, fix_ratio=FALSE, more_doses = NULL, more_responses = NULL){

    max = max(c(blue_data$Dose, red_data$Dose))
    min = min(c(blue_data$Dose, red_data$Dose))

    if (fix_ratio){
        blue_ratio = (blue_dose + red_dose)/blue_dose
        red_ratio = (blue_dose + red_dose)/red_dose
    }else{
        blue_ratio = red_ratio = 1
    }


    blue_data$Dose = blue_data$Dose * blue_ratio

    red_data$Dose = red_data$Dose * red_ratio

    min.response=min(as.numeric(c(0,response, blue_data$Response, red_data$Response, bliss_data$Response)))
    max.response=max(as.numeric(c(1,response, blue_data$Response, red_data$Response, bliss_data$Response)))

    if (!is.null(more_responses)){
        min.response=min(c(min.response, more_responses))
        max.response=max(c(max.response, more_responses))
    }

    max.response = min(c(1.2, max.response))
    min.response = max(c(-0.2, min.response))

    all.doses = c(more_doses)
    min.dose = min(all.doses)
    max.dose = max(all.doses)

    plot = ggplot(aes(x=as.numeric(Dose), y=as.numeric(Response)), data=blue_data) +
        xlim(min.dose, max.dose) +
        ylim(min.response, max.response)

    str(max.response)
    str(min.response)

    if (!is.null(more_responses)){
        len = min(c(length(more_doses), length(more_responses)))
        md=more_doses[1:len]
        me=more_responses[1:len]
        plot = plot + geom_smooth(aes(x=Dose, y=Response), data=data.frame(Dose=md, Response=me), linetype='dashed', col='black', method="loess", level=0.95, se=FALSE)
    }
    
    plot = plot +
        scale_x_log10() + 
        annotation_logticks(side='b') +
        xlab("Dose") +
        ylab("Response") +
        geom_point(data=blue_data, col='blue',cex=3,alpha=0.8) +
        geom_point(data=red_data, col='red',cex=3,alpha=0.8) +
        geom_point(data=bliss_data, col='purple',cex=3,alpha=0.8) +
        geom_smooth(data=bliss_data, linetype='dashed', col='purple',method="loess",  level=0.95, se=FALSE) +

        geom_point(x=log10(blue_dose + red_dose), y=response, col='black',cex=5,alpha=0.8) 


    if (!is.null(more_responses)){
        for (i in seq(1, len)){
            plot = plot + geom_point(x=log10(more_doses[i]), y=more_responses[i], col='black', cex=2, alpha=0.4)
        }
    }

    return(plot)
}

CI.plot_combination.hsa <- function(blue_dose, red_dose, response, blue_data, red_data, hsa_data, additive_data, fix_ratio=FALSE, more_doses = NULL, more_responses = NULL){

    max = max(c(blue_data$Dose, red_data$Dose))
    min = min(c(blue_data$Dose, red_data$Dose))

    if (fix_ratio){
        blue_ratio = (blue_dose + red_dose)/blue_dose
        red_ratio = (blue_dose + red_dose)/red_dose
    }else{
        blue_ratio = red_ratio = 1
    }


    blue_data$Dose = blue_data$Dose * blue_ratio

    red_data$Dose = red_data$Dose * red_ratio

    min.response=min(as.numeric(c(0,response, blue_data$Response, red_data$Response, hsa_data$Response)))
    max.response=max(as.numeric(c(1,response, blue_data$Response, red_data$Response, hsa_data$Response)))

    if (!is.null(more_responses)){
        min.response=min(c(min.response, more_responses))
        max.response=max(c(max.response, more_responses))
    }

    max.response = min(c(1.2, max.response))
    min.response = max(c(-0.2, min.response))

    all.doses = c(more_doses)
    min.dose = min(all.doses)
    max.dose = max(all.doses)

    plot = ggplot(aes(x=as.numeric(Dose), y=as.numeric(Response)), data=blue_data) +
        xlim(min.dose, max.dose) +
        ylim(min.response, max.response)

    str(max.response)
    str(min.response)

    if (!is.null(more_responses)){
        len = min(c(length(more_doses), length(more_responses)))
        md=more_doses[1:len]
        me=more_responses[1:len]
        plot = plot + geom_smooth(aes(x=Dose, y=Response), data=data.frame(Dose=md, Response=me), linetype='dashed', col='black', method="loess", level=0.95, se=FALSE)
    }
    
    plot = plot +
        scale_x_log10() + 
        annotation_logticks(side='b') +
        xlab("Dose") +
        ylab("Response") +
        geom_point(data=blue_data, col='blue',cex=3,alpha=0.8) +
        geom_point(data=red_data, col='red',cex=3,alpha=0.8) +
        geom_point(data=hsa_data, col='purple',cex=3,alpha=0.8) +
        geom_smooth(data=hsa_data, linetype='dashed', col='purple',method="loess",  level=0.95, se=FALSE) +

        geom_point(x=log10(blue_dose + red_dose), y=response, col='black',cex=5,alpha=0.8) 


    if (!is.null(more_responses)){
        for (i in seq(1, len)){
            plot = plot + geom_point(x=log10(more_doses[i]), y=more_responses[i], col='black', cex=2, alpha=0.4)
        }
    }

    return(plot)
}
