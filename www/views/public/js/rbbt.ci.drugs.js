//{{{ DRUGS

ci.drug_info = {}

ci.drugs = {}

ci.drugs.vm = (function(){
  var vm = {}

  vm.init = function(){


    vm.ls_key = 'rbbt.ci.drug_info'

    vm.save = function(){
      localStorage[vm.ls_key] = JSON.stringify(ci.drug_info)
    }

    vm.load = function(){
      ci.drug_info = JSON.parse(localStorage[vm.ls_key])
    }

    if (localStorage[vm.ls_key] !== undefined) vm.load()

    var init_drug = Object.keys(ci.drug_info)[0]
    vm.drug = m.prop(init_drug)
    vm.new_drug = m.prop()

    vm.dose = m.prop("")
    vm.effect = m.prop("")
    vm.median_point = m.prop(0.5)
    vm.model_type = m.prop(":LL.2()")

    vm.plot = {content: m.prop(), title: m.prop(), caption: m.prop()}

    vm.add_new_drug = function(){
      ci.drug_info[vm.new_drug()] = []
      vm.save()
      return false
    }

    vm.add_measurement = function(){
      var drug = vm.drug()
      var dose = vm.dose()
      var effect = vm.effect()
      if (undefined === ci.drug_info[drug]) ci.drug_info[drug] = {}
      ci.drug_info[drug].push([dose, effect])
      vm.save()
      return false
    }

    vm.remove_measurement = function(measurement){
      var dose = measurement.split(":")[0]
      var effect = measurement.split(":")[1]
      var drug = ci.drugs.vm.drug()
      var new_list = [];
      for (i in ci.drug_info[drug]){
        var p = ci.drug_info[drug][i]
        if (p[0] != dose || p[1] != effect) new_list.push(p)
      }
      ci.drug_info[drug] = new_list
      vm.save()
      return false
    }

    vm.remove_drug = function(drug){
     delete ci.drug_info[drug]
     console.log(ci.drug_info)
     vm.save()
     vm.drug(Object.keys(ci.drug_info)[0])
     m.redraw()
     return false
    }
  }
  return vm
}())


ci.drugs.controller = function(){
  ci.drugs.vm.init()

  this.draw_fit = function(){
    var drug = ci.drugs.vm.drug()
    var drug_info = ci.drug_info[drug]

    var doses = drug_info.map(function(p){return p[0]})
    var effects = drug_info.map(function(p){return p[1]})

    ci.drugs.vm.plot.title = m.prop('loading')
    m.redraw()

    var job_error = function(e){ci.drugs.vm.plot.content = m.prop('<div class="ui error message">Error producing plot</div>') }

    var inputs = {doses: doses.join("|"), effects: effects.join("|"), median_point: ci.controls.vm.median_point(), model_type: ci.controls.vm.model_type()}

    var job = new rbbt.Job('CombinationIndex', 'fit', inputs)

    job.run().then(ci.drugs.vm.plot.content, job_error).then(function(){
      job.get_info().then(function(info){
        if (info.status == "done"){
          ci.drugs.vm.plot.title("Fit plot for drug: " + drug)
          var caption = "The solid blue line represents the ME curve. The diamonds are the ME points."

          if (rbbt.ci.controls.vm.model_type() != 'least_squares')
            caption = caption + ' The dotted blue line is the fited curve.'

          if (info.random_samples.length > 0)
            caption = caption + ' Light blue lines are random ME curves from ME points drawn from the predictive distribution.'

          caption = caption + " ME statistics for " + drug + ": m=" + info.m.toFixed(2) + ", dm=" + info.dm.toFixed(2) + "."
          caption = caption + " GI50=" + parseFloat(info.GI50).toFixed(2)
          ci.drugs.vm.plot.caption(caption)
        }else{
          ci.drugs.vm.plot.title("Fit plot for drug: " + drug + '. Error in fit')
        }
      })
    })

    return false
  }
}

ci.drugs.view = function(controller){
  var drug_details =  ci.drugs.view.drug_details(controller)
  return [m('h3.header', "Drugs"), drug_details]
}

ci.drugs.view.drug_details = function(controller){
  var drug_details = []
  var drug_info = ci.drug_info
  var drug_tabs = []

  drug_tabs.push(m('.item.left.float.new_drug',
                    m('.ui.action.input.small', 
                      [m('input[type=text]', {placeholder: "New drug", onchange: m.withAttr('value', ci.drugs.vm.new_drug)}), 
                        m('.ui.button.icon',{onclick: ci.drugs.vm.add_new_drug},m('i.icon.plus'))
                      ])))

  drugs = Object.keys(drug_info).sort()
  for (i in drugs){
    var drug = drugs[i]
    var klass = (ci.drugs.vm.drug() == drug ? 'active' : '')
    drug_tabs.push(m('.item[data-tab=' + drug + ']', {class: klass, onclick: m.withAttr('data-tab', ci.drugs.vm.drug)}, drug))

    if (klass == 'active'){
      var table = ci.drugs.view.drug_details.measurement_table(controller, drug_info[drug])
      var new_measurement = ci.drugs.view.drug_details.measurement_new(controller, drug)
      var close_icon = m('.ui.close.icon.labeled.button', 
                         {"data-drug": drug, onclick: m.withAttr("data-drug", ci.drugs.vm.remove_drug) },
                         [m('i.icon.close'), "Remove drug"])
      var klass = (ci.drugs.vm.drug() == drug ? 'active' : '')
      details = m('.drug_details.ui.segment.tab.bottom.attached[data-tab=' + drug + ']', {class: klass}, [new_measurement, table, close_icon])
      drug_details.push(details)
    }
  }


  var tabs = m('.ui.tabular.menu.top.attached', drug_tabs)
  var plot = rbbt.mview.plot(ci.drugs.vm.plot.content(), ci.drugs.vm.plot.title(), ci.drugs.vm.plot.caption())

  var plot_column = m('.six.wide.plot.column', plot)
  return m('.ui.three.column.grid', [m('.ten.wide.column', [tabs, drug_details]), plot_column])
}

ci.drugs.view.drug_details.measurement_new = function(controller, drug){
  var dose_field = rbbt.mview.field(rbbt.mview.input('text', 'value', ci.drugs.vm.dose), "Dose")
  var effect_field = rbbt.mview.field(rbbt.mview.input('text', 'value', ci.drugs.vm.effect), "Effect")
  var fields = m('.ui.fields', [dose_field, effect_field])

  var submit = m('input[type=submit].ui.submit.button', {'data-drug': drug, onclick: m.withAttr('data-drug', ci.drugs.vm.add_measurement), value: 'Add measurement'})
  var display_plot = m('input[type=submit].ui.submit.button', {'data-drug': drug, onclick: m.withAttr('data-drug', controller.draw_fit), value: 'Display plot'})
  var buttons = m('.ui.buttons', [submit, display_plot])

  var form = m('.ui.form', [fields, buttons])

  return form
}

ci.drugs.view.drug_details.measurement_table = function(controller, measurements){

  measurements = measurements.sort(function(p1,p2){if (p1[0] == p2[0]){ return(p1[1] - p2[1])} else {return(p1[0] - p2[0])}})

  var rows = measurements.map(function(p){ 
    var dose = p[0]
    var effect = p[1]
    return ci.drugs.view.drug_details.measurement_row(controller, dose, effect)
  })

  var header = m('thead', m('tr', [m('th', 'Dose'), m('th', 'Effect'), m('th', '')]))
  var body = m('tbody', rows)
  return m('table.measurements.ui.table.collapsing.unstackable', header, body)
}

ci.drugs.view.drug_details.measurement_row = function(controller, dose, effect){
  var remove = m('i.ui.icon.minus', {measurement: [dose,effect].join(":"), onclick: m.withAttr('measurement', ci.drugs.vm.remove_measurement)})
  return m('tr', [m('td', dose), m('td', effect), m('td', remove)])
}




