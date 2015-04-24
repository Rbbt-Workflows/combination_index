
require(['rbbt.basic'], function(){

  rbbt.Job = function(workflow, task, inputs){
    this.workflow = workflow
    this.task = task
    this.inputs = inputs

    this.jobname = m.prop()
    this.jobURL = function(){ return '/' + workflow + '/' + task + '/' + this.jobname() }
    this.result = m.prop()
    this.info = m.prop()

    this.issue = function(){
      var deferred = m.deferred()
      
      if (this.jobname() !== undefined){
        deferred.resolve(this.jobname())
        return deferred.promise
      }

      var url = '/' + workflow + '/' + task

      var data = new FormData()
      data.append("_format", 'jobname')
      for (i in inputs){
        data.append(i, inputs[i])
      }

      var params = {
        url: url, 
        method: 'POST', 
        serialize: function(data) {return data},
        data: data,
        deserialize: function(value) {return value},
      }

      return rbbt.insist_request(params, deferred).then(this.jobname)
    }.bind(this)

    this.load = function(){
      var deferred = m.deferred()

      if (this.result() !== undefined){
        deferred.resolve(this.result())
        return deferred.promise
      }

      var url = add_parameter(this.jobURL(), '_format','raw')

      var data = new FormData()
      data.append("_format", 'raw')


      var params = {
        url: url, 
        method: 'GET', 
        serialize: function(data) {return data},
        deserialize: function(value) {return value},
      }

      return rbbt.insist_request(params, deferred).then(this.result)
    }.bind(this)

    this.get_info = function(){
      var deferred = m.deferred()

      if (this.info() !== undefined && (this.info().status == 'done' || this.info().status == 'error' || this.info().status == 'aborted')){
        deferred.resolve(this.info())
        return deferred.promise
      }

      var url = add_parameter(this.jobURL() + '/info', '_format','json')

      var params = {
        url: url, 
        method: 'GET', 
        serialize: function(data) {return data},
        //deserialize: function(value) {return value},
      }

      return rbbt.insist_request(params, deferred).then(this.info)
    }.bind(this)

    this.join = function(deferred, timeout){
      if (undefined === deferred) deferred = m.deferred()
      if (undefined === timeout) timeout = 1000
      if (timeout > 5000) timeout = 5000

      this.get_info().then(function(info){
        var status = info.status
        switch(status){
          case "done":
          case "error":
          case "aborted":
            deferred.resolve(info)
            break;
          default:
            setTimeout(function(){this.join(deferred, timeout*1.5)}.bind(this), timeout)
        }
      }.bind(this))

      return deferred.promise
    }.bind(this)

    this.run = function(){
      var deferred = m.deferred()

      this.issue().then(function(){
        this.join().then(function(){this.load().then(deferred.resolve, deferred.reject)}.bind(this))
      }.bind(this))

      return deferred.promise
    }.bind(this)

    this.success = function(callback){
      return this.run()
    }.bind(this)

    this.error = function(callback){
      return this.run().then(null, callback)
    }.bind(this)

  }

  rbbt.job = function(workflow, task, inputs){
    var job = new rbbt.Job(workflow, task, inputs)
    return job.run()
  }
})
