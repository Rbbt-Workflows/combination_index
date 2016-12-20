ci.controls = {}

ci.controls.vm = (function(){
  var vm = {}
  vm.init = function(){
    vm.model_type = m.prop("least_squares")
    vm.median_point = m.prop(0.5)
    vm.fix_ratio = m.prop(true)
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
        if (info.CI)
          batch[this.combination][this.response] = {value: info.CI, type: 'CI'}
        else
          if (info.bliss_excess)
            batch[this.combination][this.response] = { value: info.bliss_excess, type: 'bliss'}
          else
            batch[this.combination][this.response] = { value: info.hsa_excess, type: 'hsa'}
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

  controller.report = function(){
    var content = ci.export_controls.prepare_inputs();

    var job
    if (ci.controls.vm.model_type() == 'bliss')
      job = new rbbt.Job('CombinationIndex', 'report_bliss', {file: content, model_type: ci.controls.vm.model_type(), fix_ratio: ci.controls.vm.fix_ratio()})
    else
      if (ci.controls.vm.model_type() == 'hsa')
        job = new rbbt.Job('CombinationIndex', 'report_hsa', {file: content, model_type: ci.controls.vm.model_type(), fix_ratio: ci.controls.vm.fix_ratio()})
      else
        job = new rbbt.Job('CombinationIndex', 'report', {file: content, model_type: ci.controls.vm.model_type(), fix_ratio: ci.controls.vm.fix_ratio()})

    job.issue().then(function(){
      window.location = job.jobURL()
    }, function(){
      $(this).removeClass('loading')
      console.log("The report is still in process. Try again after a while", "Report in process")
    })
  }

  controller.batch = function(){
    ci.controls.vm.batch = {}
    ci.controls.vm.job_cache = []

    combinations = Object.keys(ci.combination_info).sort()
    for (i in combinations){
      var combination = combinations[i]

      var drugs = combination.split("-")
      var all_drugs = Object.keys(ci.drug_info)
      if (intersect(drugs,all_drugs).length == 2){
        var combination_values = ci.combination_info[combination]

        //var more_doses = combination_values.map(function(a){ return a[0] + a[1]})
        //var more_responses = combination_values.map(function(a){ return a[2]})

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

          var more_doses = []
          var more_responses = []
          var ratio = blue_dose / red_dose
          for (var i = 0; i < combination_values.length; i++){
            var pair = combination_values[i]
            var diff = Math.abs(pair[0] / pair[1] - ratio)
            if (diff < 0.001){
              more_doses.push(pair[0] + pair[1])
              more_responses.push(pair[2])
            }
          }

          inputs.more_doses = more_doses
          inputs.more_responses = more_responses

          inputs.jobname = blue_drug + '-' + red_drug

          var job
          if (model_type == 'bliss')
            job = new rbbt.Job('CombinationIndex', 'bliss', inputs)
          else
            if (model_type == 'hsa')
              job = new rbbt.Job('CombinationIndex', 'hsa', inputs)
            else
              job = new rbbt.Job('CombinationIndex', 'ci', inputs)
            

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
  var options = [
    m('.item[data-value=bliss]',option_options, "Bliss independence"), 
    m('.item[data-value=hsa]',option_options, "Highest Single Agent"), 
    m('.item[data-value=least_squares]',option_options, "Loewe additivity"),
    m('.item[data-value=LL.2]',option_options, "Loewe additivity (LL.2)"),
    m('.item[data-value=LL.3]',option_options, "Loewe additivity (LL.3)"),
    m('.item[data-value=LL.4]',option_options, "Loewe additivity (LL.4)"),
    m('.item[data-value=LL.5]',option_options, "Loewe additivity (LL.5)")]
  var model_type_input = m('.ui.selection.dropdown', {config:function(e){$(e).dropdown()}},[m('input[type=hidden]'),m('.default.text', "Loewe additivity"),m('i.dropdown.icon'), m('.menu',options)])
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

  var report_button = rbbt.mview.button({onclick: controller.report}, "Produce report")

  var control_panel 
  if (ci.controls.vm.model_type() == 'least_squares' || ci.controls.vm.model_type() == 'bliss' || ci.controls.vm.model_type() == 'hsa' )
    control_panel =  m('fieldset.ui.form',[model_type_field, fix_field, batch_button, report_button])
  else
    control_panel =  m('fieldset.ui.form',[model_type_field, median_point_field, fix_field, direct_ci_field, batch_button, report_button])

  return control_panel
}
