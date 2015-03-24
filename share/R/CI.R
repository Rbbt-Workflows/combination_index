
CI.eff_ratio = function(x){ 
    return(x / (1-x));
}

CI.add_curve = function(m_1, m_2, dm_1, dm_2, d_1, d_2){
    step = 0.00001
    additive.levels = sample(seq(step / 100,1 - step/100 ,by=step), 500)
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

