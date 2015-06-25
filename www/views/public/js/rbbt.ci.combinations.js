ci.combination_info = {}

ci.combinations = {}

ci.combinations.controller = function(){
  var controller = this
  ci.combinations.vm.init()

  controller.draw_CI = function(meassurement){
    ci.combinations.vm.plot.title = m.prop('loading')
    m.redraw()

    var combination = ci.combinations.vm.combination()

    var blue_drug = combination.split("-")[0]
    var blue_drug_info = ci.drug_info[blue_drug]
    var blue_doses = blue_drug_info.map(function(p){return p[0]})
    var blue_effects = blue_drug_info.map(function(p){return p[1]})

    var red_drug = combination.split("-")[1]
    var red_drug_info = ci.drug_info[red_drug]
    var red_doses = red_drug_info.map(function(p){return p[0]})
    var red_effects = red_drug_info.map(function(p){return p[1]})


    if (undefined === meassurement) {
      var values = ci.combination_info[combination][0]
      var blue_dose = values[0]
      var red_dose = values[1]
      var effect = values[2]
    }else{
      var values = meassurement.split(":")
      var blue_dose = parseFloat(values[0])
      var red_dose = parseFloat(values[1])
      var effect = parseFloat(values[2])
    }

    var all_values = ci.combination_info[combination]
    var more_doses = all_values.map(function(a){ return a[0] + a[1]})
    var more_effects = all_values.map(function(a){ return a[2]})

    var model_type = ci.controls.vm.model_type()

    var fix_ratio = ci.controls.vm.fix_ratio()

    var job_error = function(e){ci.combinations.vm.plot.content = m.prop('<div class="ui error message">Error producing plot</div>') }

    var inputs = {red_doses: red_doses.join("|"), red_effects: red_effects.join("|"), blue_doses: blue_doses.join("|"), blue_effects: blue_effects.join("|"), blue_dose: blue_dose, red_dose: red_dose, effect: effect, fix_ratio: fix_ratio, model_type: model_type }
    inputs.more_doses = more_doses
    inputs.more_effects = more_effects

    var job = new rbbt.Job('CombinationIndex', 'ci', inputs)

    job.run().then(function(){
      this.get_info().then(function(info){
        var job = this
        job.load().then(ci.combinations.vm.plot.content, job_error)
        var title = "Fit plot for combination: " + blue_drug + " and " + red_drug
        var caption = blue_drug + " (blue), " + red_drug + " (red), and additive combination line (black)."
        if (info.status == "done"){
          var ci_value = parseFloat(info["CI"])
          var gi50 = parseFloat(info["GI50"])

          title = title + '. CI=' + ci_value.toFixed(2)

          var random_ci = info["random_CI"]
          if (undefined !== random_ci){
            var min = Math.min.apply(null, random_ci)
            var max = Math.max.apply(null, random_ci)
            title = title + ' [' + min.toFixed(2) + ',' + max.toFixed(2) + ']'
            caption = caption + ' Dashed black lines represent additive lines for random ME-curves, and are used to calculate the CI range values.'
          }

          if (rbbt.ci.controls.vm.model_type() != ':least_squares')
            caption = caption + ' The ME-curves are adjusted to fit the effect level of the combination (median effect point).'

          var blue_dose = parseFloat(info.inputs.blue_dose)
          var red_dose = parseFloat(info.inputs.red_dose)
          var total_dose = blue_dose + red_dose
          var blue_ratio = blue_dose/total_dose
          var red_ratio = red_dose/total_dose

          var blue_gi50 = gi50 * blue_ratio
          var red_gi50 = gi50 * red_ratio
          caption = caption + ' The combination GI50 at this ratio is ' + gi50.toFixed(2) + 
            ' (' + blue_gi50.toFixed(2) + ' ' + blue_drug + ' and ' + red_gi50.toFixed(2) + ' ' + red_drug + ')'

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
  }
}


ci.combinations.vm = (function(){
  var vm = {}
  vm.init = function(){

    vm.combination = {
      drug1: m.prop(),
      drug2: m.prop(),
      dose1: m.prop(),
      dose2: m.prop(),
      effect: m.prop()
    }

    vm.ls_key = 'rbbt.ci.combination_info'

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
    vm.effect = m.prop("")
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
      var effect = vm.effect()

      if (undefined === ci.combination_info[combination]) ci.combination_info[combination] = {}
      ci.combination_info[combination].push([parseFloat(blue_dose), parseFloat(red_dose), parseFloat(effect)])
      vm.save()
      return false
    }

    vm.remove_measurement = function(measurement){
      var blue_dose = measurement.split(":")[0]
      var red_dose = measurement.split(":")[1]
      var effect = measurement.split(":")[2]
      var combination = vm.combination()
      var new_list = [];
      for (i in ci.combination_info[combination]){
        var p = ci.combination_info[combination][i]
        if (p[0] != blue_dose || p[1] != red_dose || p[2] != effect) new_list.push(p)
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

  return ci.combinations.view.combination_details(controller)
}

ci.combinations.view.get_color = function(ci_val){

  var additive = net.brehaut.Color('yellow')
  var syn = net.brehaut.Color('#0F0')
  var ant = net.brehaut.Color('#F00')
  if (ci_val == 'error'){
    color = 'blue'
  }else{
    if (ci_val > 1.2){
      a = 1 - (1 / ci_val)
      color= additive.blend(ant, a)
    }else{
      if (ci_val < 0.8){
        a = 1 - ci_val
        color= additive.blend(syn, a)
      }else{
        color= additive
      }
    }
  }
  return color
}
ci.combinations.view.combination_details = function(controller){
  var combination_details = []
  var combination_info = ci.combination_info
  var combination_tabs = []

  combination_tabs.push(m('.item.left.float.new_combination',
                          m('.ui.input.small', 
                            [
                              m('input[type=text]', {placeholder: "Blue drug", onchange: m.withAttr('value', ci.combinations.vm.blue_drug)}), 
                              m('input[type=text]', {placeholder: "Red drug", onchange: m.withAttr('value', ci.combinations.vm.red_drug)}), 
                              m('i.icon.plus',{onclick: ci.combinations.vm.add_new_combination})
                            ])))

                            combinations = Object.keys(combination_info).sort()
                            for (i in combinations){
                              var combination = combinations[i]
                              var klass = (ci.combinations.vm.combination() == combination ? 'active' : '')
                              var batch = rbbt.ci.controls.vm.batch[combination]
                              var values = []
                              var cinfo = combination_info[combination]
                              var len = Object.keys(cinfo).length
                              for (i in cinfo){
                                var triplet = cinfo[i]
                                var effect = triplet[2]
                                if (batch && batch[effect]){
                                  ci_val = batch[effect]
                                  color = ci.combinations.view.get_color(ci_val)
                                }else{
                                  color = 'grey'
                                  ci_val = 'NA'
                                }
                                var title = combination + ' ' + effect + ': ' + ci_val
                                var style = {width: '' + (100 / len) + '%', 'backgroundColor': color, 'order': (effect * 100).toInteger}
                                values.push(m('.ci_value', {title: title, 'data-effect': effect, 'data-ci': ci_val, style:style}))
                              }

                              var ci_values 

                              if (Object.keys(rbbt.ci.controls.vm.batch).length > 0 || rbbt.ci.controls.vm.running_jobs > 0)
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


                            var tabs = m('.ui.tabular.menu.top.attached', combination_tabs)
                            var plot = rbbt.mview.plot(ci.combinations.vm.plot.content(), ci.combinations.vm.plot.title(), ci.combinations.vm.plot.caption())

                            //var option_options = {onclick: m.withAttr('data-value', ci.combinations.vm.model_type)}
                            //var options = [m('.item[data-value=:LL.2()]',option_options, ":LL.2()"),m('.item[data-value=:LL.3()]',option_options, ":LL.3()"),m('.item[data-value=:LL.4()]',option_options, ":LL.4()"),m('.item[data-value=:LL.5()]',option_options, ":LL.5()")]
                            //var model_type_input = m('.ui.selection.dropdown', {config:function(e){$(e).dropdown()}},[m('input[type=hidden]'),m('.default.text', "DRC Method"),m('i.dropdown.icon'),m('.menu',options)])
                            //var fix_ratio = m('.ui.small.input', [m('label', 'Fix combination ratio'), m('input.ui.checkbox', {type: 'checkbox', checked: ci.combinations.vm.fix_ratio(),  onchange: m.withAttr('checked', ci.combinations.vm.fix_ratio)})])

                            //var plot_column = m('.five.wide.column', [model_type_input, fix_ratio, plot])

                            var plot_column = m('.five.wide.plot.column', plot)

                            return m('.ui.three.column.grid', [m('.eleven.wide.column', [tabs, combination_details]), plot_column])
}

ci.combinations.view.combination_details.measurement_new = function(controller, combination){
  var blue_dose_input = m('.input.ui.small.input', [m('label', 'Blue dose'), m('input', {type: 'text', value: ci.combinations.vm.blue_dose(), onchange: m.withAttr('value', ci.combinations.vm.blue_dose)})])
  var red_dose_input = m('.input.ui.small.input', [m('label', 'Red dose'), m('input', {type: 'text', value: ci.combinations.vm.red_dose(), onchange: m.withAttr('value', ci.combinations.vm.red_dose)})])

  var effect_input = m('.ui.small.input', [m('label', 'Effect'), m('input', {type: 'text', value: ci.combinations.vm.effect(),  onchange: m.withAttr('value', ci.combinations.vm.effect)})])
  var submit = m('input[type=submit].ui.submit.button', {'data-combination': combination, onclick: m.withAttr('data-combination', ci.combinations.vm.add_measurement), value: 'Add measurement'})
  var display_plot = m('input[type=submit].ui.submit.button', {'data-combination': combination, onclick: m.withAttr('data-combination', controller.draw_CI), value: 'Display plot'})
  //var buttons = m('.ui.buttons', [submit, display_plot])
  var buttons = m('.ui.buttons', submit)
  var form = m('.ui.form', [blue_dose_input, red_dose_input, effect_input, buttons])
  return form
}

ci.combinations.view.combination_details.measurement_table = function(controller, measurements){
  var rows = measurements.map(function(p){ 
    var blue_dose = p[0]
    var red_dose = p[1]
    var effect = p[2]
    return ci.combinations.view.combination_details.measurement_row(controller, blue_dose, red_dose, effect)
  })

  var header = m('thead', m('tr', [m('th', 'Blue dose'), m('th', 'Red dose'), m('th', 'Effect'), m('th', '')]))
  var body = m('tbody', rows)
  return m('table.measurements.ui.table.collapsing', header, body)
}

ci.combinations.view.combination_details.measurement_row = function(controller, blue_dose, red_dose, effect){
  var remove = m('i.ui.icon.minus', {measurement: [blue_dose, red_dose, effect].join(":"), onclick: m.withAttr('measurement', ci.combinations.vm.remove_measurement)})
  //var plot = m('i.ui.icon.send', {measurement: [blue_dose, red_dose, effect].join(":"), onclick: m.withAttr('measurement', controller.draw_CI)})
  var style = {}
  var batch = rbbt.ci.controls.vm.batch
  if (batch[ci.combinations.vm.combination()] && batch[ci.combinations.vm.combination()][effect])
    style['backgroundColor'] = ci.combinations.view.get_color(batch[ci.combinations.vm.combination()][effect])
  var plot = m('input[type=submit].ui.submit.button', {style: style, measurement: [blue_dose, red_dose, effect].join(":"), onclick: m.withAttr('measurement', controller.draw_CI),value: "Plot"})
  return m('tr', [m('td', blue_dose), m('td', red_dose), m('td', effect), m('td', [remove, plot])])
}


