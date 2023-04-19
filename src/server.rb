require "sinatra"
require "scale_rb"
require "yaml"
require_relative "./utils"
require_relative "../config/config.rb"
config = get_config

require "eth"
require "json"
include Eth

get "/" do
  "Hello Darwinia!"
end

get "/pangolin/rpc/:method" do
  puts config[:pangolin_rpc]
  client = Eth::Client::Http.new(config[:pangolin_rpc])

  content_type :json
  # client.eth_block_number().to_json
  client.send(:eth_block_number).to_json
end

get "/crab/stat" do
  result = File.read("./data/data.json")
  result = JSON.parse(result)

  t_list = %w[
    crab_reserved_in_staking
    ckton_reserved_in_staking
    crab_in_deposit
  ]
  if params["t"] && t_list.include?(params["t"])
    content_type :text
    return result[params["t"]].to_s
  end

  content_type :json
  { code: 0, data: result }.to_json
end

get "/crab/metadata" do
  metadata = JSON.parse(File.read(config[:metadata][:crab2]))

  content_type :json
  metadata.to_json
end

get "/crab/address/:address" do
  content_type :json
  # address must presented
  unless params[:address]
    return { code: 1, message: "address is required" }.to_json
  end

  if params[:address].length == 48
    return(
      {
        code: 0,
        data: {
          pubkey: "0x#{Address.decode(params[:address], 42, true)}",
          ss58: params[:address],
        },
      }.to_json
    )
  elsif params[:address].length == 66
    raise "Not implemented yet"
  else
    return { code: 1, message: "address is invalid" }.to_json
  end
end

get "/pangolin/templates/:filename" do
  content_type :yaml

  # check the file exists, and then render with 404
  file = File.join(__dir__, "templates", "#{params[:filename]}")
  return 404 unless File.exist? file
  File.read(file)
end

get "/pangolin/templates" do
  # get file list in templates folder
  files = Dir.entries("./templates").select { |f| f.end_with?(".yml") }
  content_type :json
  { code: 0, data: files }.to_json
end

post "/pangolin/versioned_xcm" do
  metadata = JSON.parse(File.read(config[:metadata][:pangolin2]))
  registry = Metadata.build_registry(metadata)

  # Find portable type id of VersionedXcm.
  # We just need to find type id of `PolkadotXcm.Execute`'s first param.
  call_type = Metadata.get_call_type("PolkadotXcm", "Execute", metadata)
  versioned_xcm_type_id = call_type._get(:fields).first._get(:type)

  # encode the value from request body
  value = JSON.parse(YAML.load(request.body.read).to_json)
  bytes = PortableCodec.encode(versioned_xcm_type_id, value, registry)

  content_type :json
  { code: 0, data: bytes.to_hex }.to_json
end

post "/pangolin/encode_transact_call" do
  ethereum_contract = params[:ethereum_contract][2..]
  ethereum_call = params[:ethereum_call][2..]
  pangolin_endpoint =
    params[:pangolin_endpoint].strip ||
      "0xB822E12dD225FBef8763325Aaf6F2cbCFe331c83"

  puts "pangolin_endpoint: #{pangolin_endpoint}"
  # get market fee from pangolin endpoint
  fee =
    ScaleRb::HttpClient.json_rpc_call(
      config[:pangolin_rpc],
      "eth_call",
      { data: "0xddca3f43", gas: "0x5b8d80", to: pangolin_endpoint },
      "latest",
    )
  fee = PortableCodec.u256(fee.to_i(16))

  # calculate the call data of `executeOnEthereum` function of pangolin endpoint
  call_length_hex = (ethereum_call.length / 2).to_s(16)
  data_of_execute_on_ethereum =
    "0x6c069b1f000000000000000000000000#{ethereum_contract}0000000000000000000000000000000000000000000000000000000000000040#{call_length_hex.rjust(64, "0")}#{ethereum_call}00000000000000000000000000000000000000000000000000000000"

  transact_call = {
    pallet_name: "EthereumXcm",
    call_name: "Transact",
    call: [
      {
        transact: {
          xcm_transaction: {
            V2: {
              gas_limit: PortableCodec.u256(600_000),
              action: {
                Call: pangolin_endpoint.to_bytes,
              },
              value: fee,
              input: data_of_execute_on_ethereum.to_bytes,
              access_list: "None",
            },
          },
        },
      },
      [],
    ],
  }

  metadata = JSON.parse(File.read(config[:metadata][:pangolin2]))
  encoded_call = Metadata.encode_call(transact_call, metadata)
  content_type :json
  render_json encoded_call.to_hex
end

# write a action to get substrate pallets data
# Example:
# key is empty:
# /crab/timestamp/now
# /crab/system/number
# /crab/darwinia_staking/reward_points
# /crab/vesting/vesting/
# /crab/deposit/deposits
#
# key has one parts: key1
# /crab/deposit/deposits/0x0a1287977578F888bdc1c7627781AF1cc000e6ab
# /crab/system/block_hash/0
# /crab/bridgeDarwiniaMessages/inboundLanes/0x00000000
#
# key has two parts: key1 & key2
# /crab/assets/account/0/0x0a1287977578F888bdc1c7627781AF1cc000e6ab
# /crab/assets/account/0x1234 -> error
get "/crab/:pallet_name/:storage_name/?:key1?/?:key2?" do
  pallet_name = to_camel params[:pallet_name]
  storage_name = to_camel params[:storage_name]

  puts "#{pallet_name}##{storage_name}(#{[params[:key1], params[:key2]].compact.join(", ")})"

  metadata = JSON.parse(File.read(config[:metadata][:crab2]))

  if pallet_name == "AccountMigration" && params[:key1] &&
       params[:key1].start_with?("5")
    params[:key1] = "0x#{Address.decode(params[:key1], 42, true)}"
  end

  key =
    [params[:key1], params[:key2]].compact.map { |part_of_key| c(part_of_key) }
  storage =
    ScaleRb::HttpClient.get_storage2(
      config[:crab_rpc],
      pallet_name,
      storage_name,
      key,
      metadata,
    )

  content_type :json
  render_json storage
end

error do |e|
  content_type :json
  if e.class == RuntimeError
    { code: 1, message: "#{e.message}" }.to_json
  else
    { code: 1, message: "#{e.class} => #{e.message}" }.to_json
  end
end