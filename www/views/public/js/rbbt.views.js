rbbt.mview = {}

rbbt.mview.plot = function(content, title, caption){
  var plot 

  if (undefined === title){
    plot = m('figure.ui.segment', m('.header', 'No figure to display'))
  }else{
    if (title == 'loading'){
      plot = m('figure.ui.segment.loading', 'loading figure')
    }else{
      var elems = []
      if (title) elems.push(m('.ui.header', title))
      elems.push(m('.content.svg', m.trust(content)))
      if (caption) elems.push(m('figcaption', m.trust(caption)))

      plot = m('figure.ui.segment', elems)
    }

  }

  return plot
}
