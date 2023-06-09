require "scale_rb"
require "./src/utils"
require "./src/supplies"
require "./src/metadata"
require "./src/track-goerli"
require "./src/track-pangolin"
require "./config/config.rb"
config = get_config

task default: %w[gen_supplies_data_loop]

task :update_metadata_loop do
  loop_do do
    Rake::Task["update_darwinia_metadata"].invoke
    Rake::Task["update_crab_metadata"].invoke
    Rake::Task["update_pangolin_metadata"].invoke
  end
end

task :gen_supplies_data_loop do
  loop_do { Rake::Task["gen_darwinia_supplies_data"].invoke }
end

##########################################
# Darwinia
##########################################
task :gen_darwinia_supplies_data do
  ethereum_rpc = config[:ethereum_rpc]
  darwinia_rpc = config[:darwinia_rpc]
  darwinia_metadata = JSON.parse(File.read(config[:metadata][:darwinia]))
  generate_supplies("darwinia", ethereum_rpc, darwinia_rpc, darwinia_metadata)
end

task :update_darwinia_metadata do
  darwinia_rpc = config[:darwinia_rpc]
  darwinia_metadata_path = config[:metadata][:darwinia]
  update_metadata("darwinia", darwinia_rpc, darwinia_metadata_path)
end

##########################################
# Crab
##########################################
task :update_crab_metadata do
  crab_rpc = config[:crab_rpc]
  crab_metadata_path = config[:metadata][:crab]
  update_metadata("crab", crab_rpc, crab_metadata_path)
end

##########################################
# Pangolin
##########################################
task :update_pangolin_metadata do
  pangolin_rpc = config[:pangolin_rpc]
  pangolin_metadata_path = config[:metadata][:pangolin]
  update_metadata("pangolin", pangolin_rpc, pangolin_metadata_path)
end

##########################################
# Goerli <> pangolin
##########################################
task :update_goerli_pangolin_messages do
  track_goerli
end

task :update_pangolin_goerli_messages do
  track_pangolin
end
