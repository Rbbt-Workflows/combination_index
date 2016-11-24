require 'rbbt/util/R/plot'
require 'prawn'
require 'prawn-svg'

require 'tasks/CI/fit'
require 'tasks/CI/ci'
require 'tasks/CI/bliss'

module CombinationIndex
 
  export_asynchronous :fit, :ci, :report, :bliss, :report_bliss
end
