require 'yaml'
require 'fileutils'

Dir["classes/*.rb"].each {|file| require_relative file }

tests_repo_name      = ENV['tests_repo'].split('/').last.gsub('.git','')  # Used only for folder creation snd in KPI. Should be removed
jmeter_test_path     = "/opt/tiger/jmeter_test"

test_results_folder  = "/results" #"/opt/tiger/#{ENV['test_type']}/results"
data_folder          = test_results_folder + "/data"
logs_folder          = test_results_folder + "/log"

jmeter_cmd_options   = ''
jmeter_bin_path      = '/opt/apache-jmeter-5.1.1/bin/jmeter'
tiger_influxdb_extension_path = '/opt/tiger/scripts/tiger_extensions/jmeter_tiger_extension.jmx'


[
  jmeter_test_path,
  data_folder,
  logs_folder
].each {|folder_path| FileUtils.mkdir_p(folder_path) unless File.exists?(folder_path)}

$logger=TigerLogger.new(logs_folder)

$logger.info "Clonning tests repository: git clone #{ENV['tests_repo']}"
Dir.chdir jmeter_test_path
raise "Tests were not downloaded successfully" unless system("git clone #{ENV['tests_repo']}")
Dir.chdir("#{jmeter_test_path}/#{tests_repo_name}/#{ENV['test_type']}")

test_settings_hash=YAML.load(File.read("#{jmeter_test_path}/#{tests_repo_name}/#{ENV['test_type']}/#{ENV['test_type']}.yml"))

internal_jmeter_cmd_options_hash={
  "build.id"        => ENV['current_build_number'],
  "report.csv"      => "#{data_folder}/#{ENV['test_type']}_html_report.csv",
  "errors.jtl"      => "#{data_folder}/#{ENV['test_type']}_error.jtl",
  "test.type"       => ENV['test_type'],
  "lg.id"           => ENV['lg_id'],
  "influx.protocol" => ENV['influx_protocol'],
  "influx.host"     => ENV['influx_host'],
  "influx.port"     => ENV['influx_port'],
  "influx.db"       => ENV['influx_db'],
  "project.id"      => ENV['project_id'],
  "influx.username" => ENV['influx_username'],
  "influx.password" => ENV['influx_password'],
  "env.type"        => ENV['env_type']
}

test_settings_hash['jmeter_args'].merge!(internal_jmeter_cmd_options_hash)
test_settings_hash['jmeter_args'].each {|setting,value| jmeter_cmd_options += "-J#{setting}=#{value} "}

tiger_extension_obj=TigerExtension.new(test_settings_hash['plan'],tiger_influxdb_extension_path)
extended_jmeter_plan_path=tiger_extension_obj.extend_jmeter_jmx(data_folder)

# compiling command line for the tests execution
jmeter_cmd=[
  "#{jmeter_bin_path} -n",
  "-t #{extended_jmeter_plan_path}",
  "-p #{test_settings_hash['properties']}",
  jmeter_cmd_options.chomp,
  "-l #{data_folder}/#{ENV['test_type']}.jtl",
  "-j #{logs_folder}/jmeter_#{ENV['test_type']}.log"
].join(' ')

$logger.info "Launching JMeter using compiled command line: #{jmeter_cmd}"
build_started = Time.now
jmeter_cmd_res = system(jmeter_cmd)
build_finished = Time.now 

# Getting aggregated data 
get_CSV = Influx.new()
get_CSV.get_aggregated_data_to_csv(build_started,test_results_folder)

# Applying KPI analyze
kpi    = Kpi.new(tests_repo_name,jmeter_test_path,test_results_folder)
kpi_results = kpi.kpi_analyse

# Generate JSON report
json_report = Json_report.new(build_started, build_finished)
json_report.generate_json_report(kpi_results, test_results_folder)

$logger.info jmeter_cmd_res
$logger.info "Results folder: #{test_results_folder}"
