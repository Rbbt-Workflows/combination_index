require 'rbbt/knowledge_base'
require 'rbbt/sources/organism'
require 'rbbt/sources/Miller'

module Miller

  class << self 
    attr_accessor :knowledge_base_dir
  end
  self.knowledge_base_dir = Rbbt.var.knowledge_base.Miller

  def self.survival_job
    CombinationIndex.job(:combination_index_batch, "Miller", :file => Miller.survival_values)
  end

  def self.knowledge_base
    @knowledge_base ||= begin
                          kb = KnowledgeBase.new self.knowledge_base_dir, self.organism

                          kb.register :compound_activity_change_binarized, Miller.job(:compound_activity_change_binarized).run(true).path

                          kb.register :compound_protein_changes, Miller.job(:compound_protein_changes).run(true).path

                          kb.register :compound_targets, Miller.drug_targets, :target => "Ensembl Gene ID", :type => :double
                          
                          kb.register :antibody_info, Miller.antibody_info, :target => "Ensembl Gene ID", :type => :double

                          job = survival_job
                          #tsv = job.run.to_double

                          #tsv.add_field "Compound 1" do |treatment,values|
                          #  drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
                          #  drug_name1
                          #end

                          #tsv.add_field "Compound 2" do |treatment,values|
                          #  drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
                          #  drug_name2
                          #end

                          #tsv.add_field "Dose 1" do |treatment,values|
                          #  drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
                          #  drug_dose1
                          #end

                          #tsv.add_field "Dose 2" do |treatment,values|
                          #  drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
                          #  drug_dose2
                          #end

                          #tsv.add_field "Set" do |treatment,values|
                          #  drug_name1, drug_dose1, drug_name2, drug_dose2, set = CombinationIndex.parse_combination treatment
                          #  set
                          #end


                          #tsv.process "Survival CI" do |ci|
                          #  case ci
                          #  when 0, 0.0
                          #    nil
                          #  when ""
                          #    nil
                          #  else
                          #    ci
                          #  end
                          #end

                          tsv = job.run(true).file(:flat).tsv

                          tsv.rename_field "Effect", "Survival CI"

                          kb.register :survival_CI, tsv, :source => "Compound 1=~Compound", :target => "Compound 2=~Compound", :fields => ["Survival CI", "Dose 1", "Dose 2", "Set"], :undirected => true

                          kb
                        end
  end
end
