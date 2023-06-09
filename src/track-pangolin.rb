require "dotenv/load"
require "scale_rb"
require_relative "./evm-track-helper"
require_relative "./mongodb-helper"
require_relative "../config/config.rb"

def track_pangolin
  config = get_config
  pangolin_rpc = config[:pangolin_rpc]

  # Prepare the contracts to track
  # --------------------------------------------------------
  contracts_to_track = [
    "0xAbd165DE531d26c229F9E43747a8d683eAD54C6c", # outbound lane
    "0xB59a893f5115c1Ca737E36365302550074C32023", # inbound lane
  ]

  # Prepare how to persist the last tracked block
  # --------------------------------------------------------
  get_last_tracked_block = -> do
    if MongodbHelper.get_setting("last_tracked_block_darwinia").nil?
      0
    else
      MongodbHelper.get_setting("last_tracked_block_darwinia")
    end
  end

  set_last_tracked_block = ->(number) do
    MongodbHelper.set_setting("last_tracked_block_darwinia", number)
  end

  # Main
  # --------------------------------------------------------
  evm_tracker_helper = EvmTrackHelper.new(pangolin_rpc)
  evm_tracker_helper.track_messages(
    contracts_to_track,
    get_last_tracked_block,
    set_last_tracked_block,
    20_000,
  ) do |event_name, data|
    case event_name
    when "MessageAccepted"
      message = { direction: 1 }.merge(data)
      MongodbHelper.save_or_update_message(message)
    when "MessageDispatched"
      message = { direction: 0 }.merge(data)
      MongodbHelper.save_or_update_message(message)
    when "MessagesDelivered"
      message = { direction: 1 }.merge(data)
      MongodbHelper.save_or_update_message(message)
    end
  end
end
