defmodule Logger.Backends.Logstash do
  use GenEvent

  @default_format "$time $level $node $message\n"

  def init([_]) do
    {:ok, socket} = :gen_udp.open(0)
    {:ok, configure([socket: socket])}
  end

  def handle_call({:configure, opts}, %{name: _name}) do
    {:ok, :ok, configure(opts)}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event(level, msg, ts, md, state)
    else
      {:ok, state}
    end
  end

  ## Helpers

  defp configure(options) do
    env = Application.get_env(:logger, :logger_logstash_backend, [])
    socket = Keyword.get(options, :socket)
    logstash = Keyword.merge(env, options)
    Application.put_env(:logger, :logstash, logstash)

    level = Keyword.get(logstash, :level)
    {:ok, host} = :inet.getaddr(Keyword.get(logstash, :host, '127.0.0.1'), :inet)
    port = Keyword.get(logstash, :port, 9300)
    appid = Keyword.get(logstash, :appid)
    format = Keyword.get(logstash, :format, @default_format) |> Logger.Formatter.compile
    metadata = Keyword.get(logstash, :metadata, [])
    logsource = :inet.gethostname

    %{format: format, level: level, socket: socket, host: host, port: port,
      appid: appid, logsource: logsource, metadata: metadata}
  end

  defp log_event(level, msg, ts, md, state) do
    %{socket: socket, host: host, port: port} = state
    encoded = encode_event(level, msg, ts, md, state)
    :gen_udp.send(socket, host, port, encoded)
  end

  defp encode_event(level, msg, ts, md, state) do
    %{appid: appid, logsource: logsource} = state
    :jsx.encode([fields: [level: level, appid: appid, node: node] ++ md,
                 '@timestamp': ts,
                 logsource: logsource,
                 message: msg,
                 type: :erlang])
  end
end

