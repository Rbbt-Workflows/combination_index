ci.controls = {}

ci.controls.vm = (function(){
  var vm = {}
  vm.init = function(){
    vm.model_type = m.prop(":LL.5()")
    vm.median_point = m.prop(0.5)
    vm.fix_ratio = m.prop(false)
  }

  return vm
}())


ci.controls.controller = function(){
  ci.controls.vm.init()
}

ci.controls.view = function(controller){
  var median_point_input = m('.ui.small.input', [m('label', 'Median effect point'), m('input', {type: 'text', value: ci.controls.vm.median_point(),  onchange: m.withAttr('value', ci.controls.vm.median_point)})])
  var option_options = {onclick: m.withAttr('data-value', ci.controls.vm.model_type)}
  var options = [m('.item[data-value=:least_squares]',option_options, ":least_squares"),m('.item[data-value=:LL.2()]',option_options, ":LL.2()"),m('.item[data-value=:LL.3()]',option_options, ":LL.3()"),m('.item[data-value=:LL.4()]',option_options, ":LL.4()"),m('.item[data-value=:LL.5()]',option_options, ":LL.5()")]
  var model_type_input = m('.ui.selection.dropdown', {config:function(e){$(e).dropdown()}},[m('input[type=hidden]'),m('.default.text', ci.controls.vm.model_type()),m('i.dropdown.icon'), m('.menu',options)])
  var fix_input = m('.ui.small.input', [m('label', 'Fix combination ratio'), m('input.ui.checkbox', {type: 'checkbox', checked: ci.controls.vm.fix_ratio(),  onchange: m.withAttr('checked', ci.controls.vm.fix_ratio)})])

  var control_panel =  m('.ui.basic.segment',[model_type_input, median_point_input, fix_input])
  return control_panel
}

