ci.controls = {}

ci.controls.vm = (function(){
  var vm = {}
  vm.init = function(){
    vm.model_type = m.prop("least_squares")
    vm.median_point = m.prop(0.5)
    vm.fix_ratio = m.prop(false)
    vm.direct_ci = m.prop(false)

    vm.job_cache = []
    vm.running_jobs = 0
    vm.batch = {}
  }

  return vm
}())

ci.controls.vm.batch_complete_function = function(){
  this.join().then(function(){
    this.get_info().then(function(info){
      var batch = ci.controls.vm.batch
      if (undefined === batch[this.combination]) batch[this.combination] = {}

      if (info.status == 'done')
        batch[this.combination][this.response] = info.CI
      else
        batch[this.combination][this.response] = info.status

      m.redraw()
      ci.controls.vm.running_jobs = ci.controls.vm.running_jobs - 1
      ci.controls.vm.start_job_cache()
    }.bind(this))
  }.bind(this))
}

ci.controls.vm.start_job_cache = function(){
  var job = ci.controls.vm.job_cache.shift()
  if(job != undefined){
    ci.controls.vm.running_jobs = ci.controls.vm.running_jobs + 1
    job.issue().then(ci.controls.vm.batch_complete_function.bind(job))
  }
}

ci.controls.controller = function(){
  var controller = this
  ci.controls.vm.init()

  controller.batch = function(){
    ci.controls.vm.batch = {}
    ci.controls.vm.job_cache = []

    combinations = Object.keys(ci.combination_info).sort()
    for (i in combinations){
      var combination = combinations[i]

      var drugs = combination.split("-")
      var all_drugs = Object.keys(rbbt.ci.drug_info)
      if (intersect(drugs,all_drugs).length == 2){
        var combination_values = ci.combination_info[combination]

        var more_doses = combination_values.map(function(a){ return a[0] + a[1]})
        var more_responses = combination_values.map(function(a){ return a[2]})

        for (i in combination_values){
          var combination_value = combination_values[i]

          var blue_drug = combination.split("-")[0]
          var blue_drug_info = ci.drug_info[blue_drug]
          var blue_doses = blue_drug_info.map(function(p){return p[0]})
          var blue_responses = blue_drug_info.map(function(p){return p[1]})

          var red_drug = combination.split("-")[1]
          var red_drug_info = ci.drug_info[red_drug]
          var red_doses = red_drug_info.map(function(p){return p[0]})
          var red_responses = red_drug_info.map(function(p){return p[1]})

          var blue_dose = combination_value[0]
          var red_dose = combination_value[1]
          var response = combination_value[2]

          var fix_ratio = ci.controls.vm.fix_ratio()
          var direct_ci = ci.controls.vm.direct_ci()
          var model_type = ci.controls.vm.model_type()

          var inputs = {red_doses: red_doses.join("|"), red_responses: red_responses.join("|"), blue_doses: blue_doses.join("|"), blue_responses: blue_responses.join("|"), blue_dose: blue_dose, red_dose: red_dose, response: response, fix_ratio: fix_ratio, model_type: model_type, direct_ci: direct_ci}
          inputs.more_doses = more_doses
          inputs.more_responses = more_responses

          inputs.jobname = blue_drug + '-' + red_drug

          var job = new rbbt.Job('CombinationIndex', 'ci', inputs)

          job.combination = combination
          job.response = response

          ci.controls.vm.job_cache.push(job)
        }
      }
    }
    ci.controls.vm.start_job_cache()
    ci.controls.vm.start_job_cache()
    ci.controls.vm.start_job_cache()
    ci.controls.vm.start_job_cache()
  }
}

ci.controls.view = function(controller){

  var option_options = {onclick: m.withAttr('data-value', ci.controls.vm.model_type)}
  var options = [m('.item[data-value=least_squares]',option_options, "least_squares"),m('.item[data-value=LL.2]',option_options, "LL.2"),m('.item[data-value=LL.3]',option_options, "LL.3"),m('.item[data-value=LL.4]',option_options, "LL.4"),m('.item[data-value=LL.5]',option_options, "LL.5")]
  var model_type_input = m('.ui.selection.dropdown', {config:function(e){$(e).dropdown()}},[m('input[type=hidden]'),m('.default.text', ci.controls.vm.model_type()),m('i.dropdown.icon'), m('.menu',options)])
  var model_type_field = rbbt.mview.field(model_type_input, "Model type")

  var median_point_field = rbbt.mview.field(
    rbbt.mview.input('text', 'value', ci.controls.vm.median_point), 
    "Median response point for ME points in single drug plot"
  )

  var fix_field = rbbt.mview.field(
    rbbt.mview.input('checkbox', 'checked', ci.controls.vm.fix_ratio, {id: 'fixratioinput'}), 
    "Fix dosage ratio in combination plot"
  )

  var direct_ci_field = rbbt.mview.field(
    rbbt.mview.input('checkbox', 'checked', ci.controls.vm.direct_ci, {id: 'directciinput'}), 
    "Compute CI directly from the dose-response fit (instead of using ME points)"
  )


  var batch_button = rbbt.mview.button({onclick: controller.batch}, "Analyze All in Batch")

  var control_panel 
  if (ci.controls.vm.model_type() == 'least_squares')
    control_panel =  m('fieldset.ui.form',[model_type_field, fix_field, batch_button])
  else
    control_panel =  m('fieldset.ui.form',[model_type_field, median_point_field, fix_field, direct_ci_field, batch_button])

  return control_panel
}
