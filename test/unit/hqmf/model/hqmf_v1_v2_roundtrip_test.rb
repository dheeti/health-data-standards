require 'fileutils'
require_relative '../../../test_helper'

class HQMFV1V2RoundtripTest < Test::Unit::TestCase
  RESULTS_DIR = 'tmp/hqmf_r2.1_roundtrip_diffs'

  # Create a blank folder for the errors
  FileUtils.rm_rf(RESULTS_DIR) if File.directory?(RESULTS_DIR)
  Dir.mkdir RESULTS_DIR

  # Automatically generate one test method per measure file
  measure_files = File.join('test', 'fixtures', '1.0', 'measures', 'e{p,h}_0033.xml')
  Dir.glob(measure_files).each do | measure_filename |
    measure_name = /.*[\/\\]((ep|eh)_.*)\.xml/.match(measure_filename)[1]
    define_method("test_#{measure_name}") do
      do_roundtrip_test(measure_filename, measure_name)
    end
  end

  def do_roundtrip_test(measure_filename, measure_name)
    # open the v1 file and generate a v2.1 xml string
    v1_model = HQMF::Parser.parse(File.open(measure_filename).read, '1.0')

    skip('Continuous Variable measures currently not supported') if v1_model.population_criteria('MSRPOPL')

    hqmf_xml = HQMF2::Generator::ModelProcessor.to_hqmf(v1_model)
    v2_model = HQMF::Parser.parse(hqmf_xml, '2.0')

    v1_json = JSON.parse(v1_model.to_json.to_json)
    v2_json = JSON.parse(v2_model.to_json.to_json)

    update_v1_json(v1_json)

    diff = v1_json.diff_hash(v2_json, true, true)

    unless diff.empty?
      outfile = File.join("#{RESULTS_DIR}","#{measure_name}_diff.json")
      File.open(outfile, 'w') {|f| f.write(JSON.pretty_generate(JSON.parse(diff.to_json))) }
      outfile = File.join("#{RESULTS_DIR}","#{measure_name}_r1.json")
      File.open(outfile, 'w') {|f| f.write(JSON.pretty_generate(v1_json)) }
      outfile = File.join("#{RESULTS_DIR}","#{measure_name}_r2.json")
      File.open(outfile, 'w') {|f| f.write(JSON.pretty_generate(v2_json)) }
      outfile = File.join("#{RESULTS_DIR}","#{measure_name}_r2.xml")
      File.open(outfile, 'w') {|f| f.write(hqmf_xml) }
    end

    assert diff.empty?, 'Differences in model after roundtrip to HQMF V2'
  end

  def update_v1_json(v1_json)
    # remove measure period width
    v1_json['measure_period']['width'] = nil
    
    # remove embedded whitespace formatting in attribute values
    v1_json['attributes'].each do |attr|
      if attr['value']
        attr['value'].gsub!(/\n/, ' ')
      end
      if attr['value_obj'] && attr['value_obj']['value']
        attr['value_obj']['value'].gsub!(/\n/, ' ')
      end
    end

    # drop the CMS ID since it does not go into the HQMF v2
    if v1_json['cms_id']
      puts "\t CMS ID ignored in hqmf v2"
      v1_json['cms_id'] = nil
    end

    # v2 switches negated preconditions non-negated equivalents (atLeastOneTrue[negated] -> allFalse)
    fix_precondition_negations(v1_json['population_criteria'])

    # v2 ranges (in pauseQuantity) cannot be IVL_PQ, so change to PQ
    fix_range_types(v1_json)
  end

  def fix_precondition_negations(root)
    if (HQMF::Precondition::NEGATIONS.keys.include?(root['conjunction_code']) && root['negation'])
      root['conjunction_code'] = HQMF::Precondition::NEGATIONS[root['conjunction_code']]
      root.delete('negation')
    end

    root.each_value do |value|
      if value.is_a? Hash
        fix_precondition_negations(value)
      elsif value.is_a? Array
        value.each {|entry| fix_precondition_negations(entry) if entry.is_a? Hash}
      end
    end
  end

  def fix_range_types(root)
    if (root['temporal_references'])
      root['temporal_references'].each do |tr|
        if tr['range'] && tr['range']['type'] == 'IVL_PQ'
          tr['range']['type'] = 'PQ'
        end
      end
    end

    root.each_pair do |key, value|
      if value.is_a? Hash
        fix_range_types(value)
      elsif value.is_a? Array and key != 'temporal_references'
        value.each {|entry| fix_range_types(entry) if entry.is_a? Hash}
      end
    end
  end
end
