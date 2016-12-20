require 'rbbt-util'
require 'rbbt/workflow'
require 'rbbt/util/R'

require_relative 'lib/combination_index'

module CombinationIndex
  extend Workflow
  COMBINATION_SEP = "-"

end

require_relative 'lib/tasks/CI.rb'
