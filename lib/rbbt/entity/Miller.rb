require 'rbbt/entity'

module Compound
  extend Entity

  self.format = "Compound"

  property :activated_genes => :single do
    Miller.knowledge_base.subset(:compound_protein_changes, :source => self).select("Effect" => "activated").target
  end
end

module Antibody
  extend Entity
  self.format = ["Antibody", "Cannonical"]

  def self.id_options
    {:persist => true}
  end

  def self.id_file
    Miller.data.antibody_info
  end

  def self.id_index(format = nil)

    @@id_index ||=  {}
    @@id_index[format] ||= begin
                             format ||= id_options[:default] || self.formats.first
                             TSV.index id_file, id_options.merge(:target => format)
                           end
  end

  property :gene => :single do
    format = "Ensembl Gene ID"
    gene = Antibody.id_index(format)[self]
    Gene.setup(gene, format, Miller.organism)
  end
end

module Combination
  extend Entity
  self.format = "Combination"

  property :combination_info => :single do
    case
    when (m = self.match(/(.+)=(.+)-(.+)=([^\s]+)(?: set (\d))?/))
      drug_name1, drug_dose1, drug_name2, drug_dose2, set = m.captures
    when (m = self.match(/(.+)-(.+)=(.+)-([^\s]+)(?: set (\d))?/))
      drug_name1, drug_name2, drug_dose1, drug_dose2, set = m.captures
    else
      raise "Combination format not understood: #{self}"
    end

    {
      :drug2 => drug_name2, 
      :dose2 => drug_dose2, 
      :drug1 => drug_name1, 
      :dose1 => drug_dose1, 
      :set => set
    } 
  end
end
