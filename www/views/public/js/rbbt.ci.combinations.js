ci.combination_info = {}

ci.combinations = {}

ci.combinations.controller = function(){
  var controller = this
  ci.combinations.vm.init()

  controller.draw_CI = rbbt.try(function(meassurement){
    ci.combinations.vm.plot.title = m.prop('loading')
    m.redraw()

    var combination = ci.combinations.vm.combination()

    var blue_drug = combination.split("-")[0]
    var blue_drug_info = ci.drug_info[blue_drug]
    rbbt.exception.null(blue_drug_info, "Drug " + blue_drug + " was not found")
    var blue_doses = blue_drug_info.map(function(p){return p[0]})
    var blue_responses = blue_drug_info.map(function(p){return p[1]})

    var red_drug = combination.split("-")[1]
    var red_drug_info = ci.drug_info[red_drug]
    rbbt.exception.null(red_drug_info, "Drug " + red_drug + " was not found")
    var red_doses = red_drug_info.map(function(p){return p[0]})
    var red_responses = red_drug_info.map(function(p){return p[1]})


    if (undefined === meassurement) {
      var values = ci.combination_info[combination][0]
      var blue_dose = values[0]
      var red_dose = values[1]
      var response = values[2]
    }else{
      var values = meassurement.split(":")
      var blue_dose = parseFloat(values[0])
      var red_dose = parseFloat(values[1])
      var response = parseFloat(values[2])
    }

    var all_values = ci.combination_info[combination]
    
    var more_doses = []
    var more_responses = []
    var ratio = blue_dose / red_dose
    for (var i = 0; i < all_values.length; i++){
      var pair = all_values[i]
      var diff = Math.abs(pair[0] / pair[1] - ratio)
      if (diff < 0.001){
        more_doses.push(pair[0] + pair[1])
        more_responses.push(pair[2])
      }
    }

    var model_type = ci.controls.vm.model_type()

    var fix_ratio = ci.controls.vm.fix_ratio()

    var direct_ci = ci.controls.vm.direct_ci()

    var job_error = function(e){ci.combinations.vm.plot.content = m.prop('<div class="ui error message">Error producing plot</div>') }

    var inputs = {red_doses: red_doses.join("|"), red_responses: red_responses.join("|"), blue_doses: blue_doses.join("|"), blue_responses: blue_responses.join("|"), blue_dose: blue_dose, red_dose: red_dose, response: response, fix_ratio: fix_ratio, model_type: model_type, direct_ci: direct_ci}
    inputs.more_doses = more_doses
    inputs.more_responses = more_responses
    inputs.jobname = combination

    var job;
    if (model_type == 'bliss')
      job = new rbbt.Job('CombinationIndex', 'bliss', inputs);
    else
      if (model_type == 'hsa')
        job = new rbbt.Job('CombinationIndex', 'hsa', inputs);
      else
        job = new rbbt.Job('CombinationIndex', 'ci', inputs);

    job.run().then(function(){
      this.get_info().then(function(info){
        var job = this
        job.load().then(ci.combinations.vm.plot.content, job_error)
        var title = "Fit plot for combination: " + blue_drug + " and " + red_drug

        var caption = blue_drug + " (blue), " + red_drug + " (red) ME curves, "

        if (info.status == "done"){
          var value 

          if (info.CI){
            value = info.CI
            title = title + ' ' + "--" + " CI = " + value.toFixed(2)
            caption = caption + " and additive combination line (black)."
          }else{
            if (info.bliss_excess){
              value = info.bliss_excess
              title = title + ' ' + "--" + ' Bliss excess = ' + value.toFixed(2)
              if (info.bliss_pvalue){
                pvalue =  info.bliss_pvalue
                if (pvalue < 0.00001) pvalue = 0.00001
                title = title + '; P-value = ' + pvalue.toFixed(5)
              }
              caption = caption + " and bliss average additive line (purple dashed). Purple points are bliss scores for each pair of blue and red drug responses at those dosages.";
            }else{
              value = info.hsa_excess
              title = title + ' ' + "--" + ' HSA excess = ' + value.toFixed(2)
              caption = caption + " and highest single agent line (purple dashed)."
            }
          }

          caption = caption + " Combination values at the same dosage ratio are represented (black dots; current one is larger) and fit with loess (black dashed)."
            
          value = parseFloat(value)

          var gi50
          if (info.gi50)
            gi50 = parseFloat(info["GI50"])


          if (ci.controls.vm.model_type() != 'least_squares' && ci.controls.vm.model_type() != 'bliss')
            caption = caption + ' The ME-curves are adjusted to fit the response level of the combination (median response point). The red and blue dashed lines are the model fit curves.'

          if (info["random_CI"]){
            var random_ci = info["random_CI"]
            if (random_ci.length > 0){
              var min = Math.min.apply(null, random_ci)
              var max = Math.max.apply(null, random_ci)
              title = title + ' [ ' + min.toFixed(2) + ', ' + max.toFixed(2) + ' ]'
              caption = caption + ' Light blue lines represent additive lines for random ME-curves, and are used to calculate the CI range values.'
            }
          }

          if (info.fit_dose_d1 !== undefined)
            caption = caption + ' Blue and red vertical dotted lines represents the dosages for each drug that achieve the same response as the combination and are used for the CI calculation (instead of the ME points).'

          var blue_dose = parseFloat(info.inputs.blue_dose)
          var red_dose = parseFloat(info.inputs.red_dose)
          var total_dose = blue_dose + red_dose
          var blue_ratio = blue_dose/total_dose
          var red_ratio = red_dose/total_dose

          var blue_gi50;
          var red_gi50;

          if (gi50){
            blue_gi50 = gi50 * blue_ratio
            red_gi50 = gi50 * red_ratio

            caption = caption + ' The combination GI50 at this ratio is ' + gi50.toFixed(2) + 
              ' (' + blue_gi50.toFixed(2) + ' ' + blue_drug + ' and ' + red_gi50.toFixed(2) + ' ' + red_drug + ')'
          }


          ci.combinations.vm.plot.title(title)
          ci.combinations.vm.plot.caption(caption)
        }else{
          title = title + ' Could not calculate CI value'
          ci.combinations.vm.plot.title(title)
        }
        m.redraw()
      }.bind(this))
    }.bind(job))

    return false
  })
}


ci.combinations.vm = (function(){
  var vm = {}
  vm.init = function(){

    vm.combination = {
      drug1: m.prop(),
      drug2: m.prop(),
      dose1: m.prop(),
      dose2: m.prop(),
      response: m.prop()
    }

    vm.ls_key = 'ci.combination_info'

    vm.save = function(){
      localStorage[vm.ls_key] = JSON.stringify(ci.combination_info)
    }

    vm.load = function(){
      ci.combination_info = JSON.parse(localStorage[vm.ls_key])
    }

    if (localStorage[vm.ls_key] !== undefined && localStorage[vm.ls_key] != '') vm.load()

    var init_combination = Object.keys(ci.combination_info)[0]
    vm.combination = m.prop(init_combination)

    vm.blue_drug = m.prop("")
    vm.red_drug = m.prop("")

    vm.model_type = m.prop()

    vm.new_combination = function(){
      return [vm.blue_drug(), vm.red_drug()].join("-")
    }

    vm.blue_dose = m.prop("")
    vm.red_dose = m.prop("")
    vm.response = m.prop("")
    vm.fix_ratio = m.prop(false)

    vm.plot = {content: m.prop(), title: m.prop(), caption: m.prop()}

    vm.add_new_combination = function(){
      ci.combination_info[vm.new_combination()] = []
      vm.save()
      return false
    }

    vm.add_measurement = function(){
      var combination = vm.combination()
      var blue_dose = vm.blue_dose()
      var red_dose = vm.red_dose()
      var response = vm.response()

      if (undefined === ci.combination_info[combination]) ci.combination_info[combination] = {}
      ci.combination_info[combination].push([parseFloat(blue_dose), parseFloat(red_dose), parseFloat(response)])
      vm.save()
      return false
    }

    vm.remove_measurement = function(measurement){
      var blue_dose = measurement.split(":")[0]
      var red_dose = measurement.split(":")[1]
      var response = measurement.split(":")[2]
      var combination = vm.combination()
      var new_list = [];
      for (i in ci.combination_info[combination]){
        var p = ci.combination_info[combination][i]
        if (p[0] != blue_dose || p[1] != red_dose || p[2] != response) new_list.push(p)
      }
      ci.combination_info[combination] = new_list
      vm.save()
      return false
    }

    vm.remove_combination = function(combination){
     delete ci.combination_info[combination]
     vm.save()
     vm.combination(Object.keys(ci.combination_info)[0])
     m.redraw()
     return false
    }
  }
  return vm
}())

ci.combinations.view = function(controller){

  return [m('h3.header', "Combinations"), ci.combinations.view.combination_details(controller)]
}

ci.combinations.view.get_color_bliss = function(bliss_val){

  var additive = net.brehaut.Color('yellow')
  var syn = net.brehaut.Color('#0F0')
  var ant = net.brehaut.Color('#F00')
  if (bliss_val == 'error'){
    color = 'blue'
  }else{
    if (bliss_val > 0){
      color= additive.blend(ant, 0.1 + bliss_val*0.9)
    }else{
      if (bliss_val < -0){
        color= additive.blend(syn, 0.1 - bliss_val*0.9)
      }else{
        color= additive
      }
    }
  }
  return color
}
ci.combinations.view.get_color_ci = function(ci_val){

  var additive = net.brehaut.Color('yellow')
  var syn = net.brehaut.Color('#0F0')
  var ant = net.brehaut.Color('#F00')
  if (ci_val == 'error'){
    color = 'blue'
  }else{
    if (ci_val > 1.2){
      a = 1 - (1 / ci_val)
      color= additive.blend(ant, 0.1 + a*0.9)
    }else{
      if (ci_val < 0.8){
        a = 1 - ci_val
        a = (Math.exp(Math.pow(1-ci_val,3)) - 1)/(Math.exp(1) - 1)
        color= additive.blend(syn, 0.1 + a*0.9)
      }else{
        color= additive
      }
    }
  }
  return color
}

ci.combinations.view.get_color = function(val){
  if (val == 'error')
    return ci.combinations.view.get_color_ci(val)

  if (val.type == 'CI')
    return ci.combinations.view.get_color_ci(val.value)

  return ci.combinations.view.get_color_bliss(val.value)
}

ci.combinations.view.combination_details = function(controller){
  var combination_details = []
  var combination_info = ci.combination_info
  var combination_tabs = []

  var new_combination = m('.ui.action.input.small', 
                            [
                              m('input[type=text]', {placeholder: "Blue drug", onchange: m.withAttr('value', ci.combinations.vm.blue_drug)}), 
                              m('input[type=text]', {placeholder: "Red drug", onchange: m.withAttr('value', ci.combinations.vm.red_drug)}), 
                              m('.ui.icon.button',{onclick: ci.combinations.vm.add_new_combination}, m('i.icon.plus'))
                            ])
  //combination_tabs.push(m('.item.left.float.new_combination',new_combination))

  combinations = Object.keys(combination_info).sort()
  for (i in combinations){
    var combination = combinations[i]

    var drugs = combination.split("-")
    var all_drugs = Object.keys(ci.drug_info)

    if (intersect(drugs,all_drugs).length == 2){
      var klass = (ci.combinations.vm.combination() == combination ? 'active' : '')
      var batch = ci.controls.vm.batch[combination]
      var values = []
      var cinfo = combination_info[combination]
      var len = Object.keys(cinfo).length
      var diff_ratios = false
      cinfo = cinfo.sort(function(p1,p2){
        if ((p1[0] / p1[1]) == (p2[0] / p2[1])){
          if (p1[0] == p2[0]){ 
            if (p1[1] == p2[1]){ 
              return(p1[2] - p2[2])
            }else{
              return(p1[1] - p2[1])
            }
          } else {return(p1[0] - p2[0])}
        }else{
          diff_ratios = true
          return((p1[0] / p1[1]) - (p2[0] / p2[1]))
        }

      })

      for (i in cinfo){
        var triplet = cinfo[i]
        var response = triplet[2]
        if (batch && batch[response]){
          ci_val = batch[response]
          color = ci.combinations.view.get_color(ci_val)
        }else{
          color = 'grey'
          ci_val = 'NA'
        }
        var title = combination + ' ' + response + ': ' + ci_val
        var style = {width: '' + (100 / len) + '%', 'backgroundColor': color, 'order': (response * 100).toInteger}
        values.push(m('.ci_value', {title: title, 'data-response': response, 'data-ci': ci_val, style:style}))
      }

      var ci_values 

      if (Object.keys(ci.controls.vm.batch).length > 0 || ci.controls.vm.running_jobs > 0)
        ci_values = m('.ci_values', values)
      else
        ci_values = []

      var tab = m('.item[data-tab=' + combination + ']', {class: klass, onclick: m.withAttr('data-tab', ci.combinations.vm.combination)}, [ci_values, combination])
      combination_tabs.push(tab)

      if (klass == 'active'){
        var table = ci.combinations.view.combination_details.measurement_table(controller, combination_info[combination])
        var close_icon = m('.ui.close.icon.labeled.button', 
                            {"data-combination": combination, onclick: m.withAttr("data-combination", ci.combinations.vm.remove_combination) },
                            [m('i.icon.close'), "Remove combination"])

                            var new_measurement = ci.combinations.view.combination_details.measurement_new(controller, combination)
                            details = m('.combination_details.ui.segment.tab.bottom.attached[data-tab=' + combination + ']', {class: klass}, [new_measurement, table, close_icon])

                            combination_details.push(details)
      }
    }
  }


  var tabs = m('.ui.tabular.menu.top.attached', combination_tabs)
  var plot = rbbt.mview.plot(ci.combinations.vm.plot.content(), ci.combinations.vm.plot.title(), ci.combinations.vm.plot.caption())

  //var option_options = {onclick: m.withAttr('data-value', ci.combinations.vm.model_type)}
  //var options = [m('.item[data-value=:LL.2()]',option_options, ":LL.2()"),m('.item[data-value=:LL.3()]',option_options, ":LL.3()"),m('.item[data-value=:LL.4()]',option_options, ":LL.4()"),m('.item[data-value=:LL.5()]',option_options, ":LL.5()")]
  //var model_type_input = m('.ui.selection.dropdown', {config:function(e){$(e).dropdown()}},[m('input[type=hidden]'),m('.default.text', "DRC Method"),m('i.dropdown.icon'),m('.menu',options)])
  //var fix_ratio = m('.ui.small.input', [m('label', 'Fix combination ratio'), m('input.ui.checkbox', {type: 'checkbox', checked: ci.combinations.vm.fix_ratio(),  onchange: m.withAttr('checked', ci.combinations.vm.fix_ratio)})])

  //var plot_column = m('.five.wide.column', [model_type_input, fix_ratio, plot])

  var plot_column = m('.six.wide.plot.column', plot)

  return m('.ui.three.column.grid', [m('.ten.wide.column', [new_combination, tabs, combination_details]), plot_column])
}

ci.combinations.view.combination_details.measurement_new = function(controller, combination){

  var blue_dose_field = rbbt.mview.field(rbbt.mview.input('text', 'value', ci.combinations.vm.blue_dose), "Blue dose")
  var red_dose_field = rbbt.mview.field(rbbt.mview.input('text', 'value', ci.combinations.vm.red_dose), "Red dose")
  var response_field = rbbt.mview.field(rbbt.mview.input('text', 'value', ci.combinations.vm.response), "Response")
  var fields = m('.ui.fields', [blue_dose_field, red_dose_field, response_field])

  var submit = m('input[type=submit].ui.submit.button', {'data-combination': combination, onclick: m.withAttr('data-combination', ci.combinations.vm.add_measurement), value: 'Add measurement'})
  var display_plot = m('input[type=submit].ui.submit.button', {'data-combination': combination, onclick: m.withAttr('data-combination', controller.draw_CI), value: 'Display plot'})
  var buttons = m('.ui.buttons', submit)

  var form = m('.ui.form', [fields, buttons])
  return form
}

ci.combinations.view.combination_details.measurement_table = function(controller, measurements){
  var rows = measurements.map(function(p){ 
    var blue_dose = p[0]
    var red_dose = p[1]
    var response = p[2]
    return ci.combinations.view.combination_details.measurement_row(controller, blue_dose, red_dose, response)
  })

  var header = m('thead', m('tr', [m('th', 'Blue dose'), m('th', 'Red dose'), m('th', 'Response'), m('th', '')]))
  var body = m('tbody', rows)
  return m('table.measurements.ui.table.collapsing.unstackable', header, body)
}

ci.combinations.view.combination_details.measurement_row = function(controller, blue_dose, red_dose, response){
  var remove = m('i.ui.icon.minus', {measurement: [blue_dose, red_dose, response].join(":"), onclick: m.withAttr('measurement', ci.combinations.vm.remove_measurement)})
  //var plot = m('i.ui.icon.send', {measurement: [blue_dose, red_dose, response].join(":"), onclick: m.withAttr('measurement', controller.draw_CI)})
  var style = {}
  var batch = ci.controls.vm.batch
  if (batch[ci.combinations.vm.combination()] && batch[ci.combinations.vm.combination()][response]){
    style['backgroundColor'] = ci.combinations.view.get_color(batch[ci.combinations.vm.combination()][response])
    if (batch[ci.combinations.vm.combination()][response].value > 5){
      val_str = "> 5"
    }else{
      if (batch[ci.combinations.vm.combination()][response].value.toFixed){
        val_str = " " + batch[ci.combinations.vm.combination()][response].value.toFixed(2);
      }else{
        val_str = ""
      }
    }
  }else{
    val_str = ""
  }

  var plot = m('input[type=submit].ui.submit.button', {style: style, measurement: [blue_dose, red_dose, response].join(":"), onclick: m.withAttr('measurement', controller.draw_CI),value: "Plot" + val_str})
  return m('tr', [m('td', blue_dose), m('td', red_dose), m('td', response), m('td', [remove, plot])])
}


