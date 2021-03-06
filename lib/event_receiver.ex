defmodule Aprb.EventReceiver do
  require Logger
  alias Aprb.{Repo, Topic}

  def start_link(channel) do
    KafkaEx.create_worker(String.to_atom(channel))
    for message <- KafkaEx.stream(channel, 0, worker_name: String.to_atom(channel), offset: latest_offset(channel)), acceptable_message?(message.value) do
      proccessed_message = process_message(message, channel)
      # broadcast a message to a channel
      for subscriber <- get_topic_subscribers(channel) do
        Slack.Web.Chat.post_message("##{subscriber.channel_name}", proccessed_message)
      end
    end
  end

  defp latest_offset(channel) do
    KafkaEx.latest_offset(channel, 0)
        |> List.first
        |> Map.get(:partition_offsets)
        |> List.first
        |> Map.get(:offset)
        |> List.first
  end

  defp acceptable_message?(message) do
    try do
      Poison.decode!(message)
        |> is_map
    rescue
      Poison.SyntaxError -> false
    end
  end

  defp process_message(message, channel) do
    event = Poison.decode!(message.value)
    case channel do
      "users" ->
        ":heart: #{cleanup_name(event["subject"]["display"])} #{event["verb"]} #{event["properties"]["artist"]["name"]}"
      "subscriptions" ->
        ":moneybag: #{cleanup_name(event["subject"]["display"])} #{event["verb"]} #{event["properties"]["partner"]["name"]}"
      "inquiries" ->
        ":shaka: #{cleanup_name(event["subject"]["display"])} #{event["verb"]} #{event["properties"]["inquireable"]["name"]}"
    end
  end

  defp get_topic_subscribers(topic_name) do
    topic = Repo.get_by(Topic, name: topic_name)
              |> Repo.preload(:subscribers)
    topic.subscribers
  end

  defp cleanup_name(full_name) do
    full_name
      |> String.split
      |> List.first
  end
end