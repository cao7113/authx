defmodule Authx.Mailer do
  use Swoosh.Mailer, otp_app: :authx

  def local_preview? do
    local?() && adapter() == Swoosh.Adapters.Local
  end

  def local? do
    # swoosh Application load Swoosh.Adapters.Local.Storage.Manager by default from
    # deps/swoosh/lib/swoosh/application.ex
    # normally set it to false in production but special needs
    Application.get_env(:swoosh, :local, true)
  end

  def adapter do
    Application.get_env(:authx, __MODULE__) |> Keyword.get(:adapter)
  end

  def from_no_reply do
    {"noreply", "noreply@#{Authx.phx_host()}"}
  end
end
