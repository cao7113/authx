defmodule AuthxWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{
    Components,
    ConfirmLive,
    MagicSignInLive,
    ResetLive,
    SignInLive,
    SignOutLive
  }

  @page_class """
  flex min-h-[calc(100vh-4.5rem)] items-start justify-center bg-[#fafbf8]
  px-5 py-10 sm:items-center sm:px-8 sm:py-16
  """

  @card_class """
  auth-card w-full max-w-md rounded-[1.75rem] border border-[#dfe8db] bg-white
  p-6 shadow-[0_20px_65px_-30px_rgba(32,70,43,0.22)] sm:p-9
  """

  @input_class """
  block w-full rounded-xl border bg-white px-4 py-3 text-sm text-[#18271f]
  shadow-sm transition placeholder:text-[#a0aea2] focus:outline-none focus:ring-4
  """

  @button_class """
  mt-5 inline-flex w-full cursor-pointer items-center justify-center rounded-full
  bg-[#1d4936] px-5 py-3 text-sm font-semibold text-white transition-colors
  hover:bg-[#2f6048] focus-visible:outline-2 focus-visible:outline-offset-2
  focus-visible:outline-[#3a7053] disabled:cursor-not-allowed disabled:opacity-60
  """

  @heading_class "mb-4 text-xl font-semibold tracking-tight text-[#1d4936]"

  override SignInLive do
    set :root_class, @page_class
  end

  override ResetLive do
    set :root_class, @page_class
  end

  override ConfirmLive do
    set :root_class, @page_class
  end

  override MagicSignInLive do
    set :root_class, @page_class
  end

  override SignOutLive do
    set :root_class, @page_class
  end

  override Components.SignIn do
    set :root_class, @card_class
    set :strategy_class, "w-full"
    set :authentication_error_container_class, "text-center text-sm text-red-700"
    set :dev_mailbox_container_class, "w-full text-center"
    set :dev_mailbox_link_class, "mt-4 block text-sm text-[#578064] hover:text-[#173b2a]"
  end

  override Components.Reset do
    set :root_class, @card_class
    set :strategy_class, "w-full"
  end

  override Components.Reset.Form do
    set :label_class, @heading_class
  end

  override Components.Confirm do
    set :root_class, @card_class
    set :strategy_class, "w-full"
  end

  override Components.MagicLink.SignIn do
    set :root_class, @card_class
    set :strategy_class, "w-full"
  end

  override Components.Banner do
    set :image_url, nil
    set :dark_image_url, nil
    set :href_url, nil
    set :root_class, "auth-banner mb-8 text-center"
    set :text, "一处身份，多处连接。"
    set :text_class, "text-2xl font-semibold tracking-tight text-[#1d4936]"
  end

  override Components.Password do
    set :root_class, "mb-5"
    set :interstitial_class, "flex flex-wrap justify-between gap-2 text-sm font-medium"
    set :toggler_class, "text-[#578064] transition-colors hover:text-[#173b2a]"
  end

  override Components.Password.SignInForm do
    set :label_class, @heading_class
  end

  override Components.Password.RegisterForm do
    set :label_class, @heading_class
  end

  override Components.Password.ResetForm do
    set :label_class, @heading_class
  end

  override Components.Password.Input do
    set :field_class, "mt-4"
    set :label_class, "mb-2 block text-sm font-medium text-[#415348]"

    set :input_class,
        @input_class <> " border-[#d6dfd5] focus:border-[#659776] focus:ring-[#e5f1e2]"

    set :input_class_with_error,
        @input_class <> " border-red-400 focus:border-red-500 focus:ring-red-100"

    set :submit_class, @button_class
    set :error_ul, "mt-2 text-sm text-red-700"
    set :remember_me_class, "mt-4 flex items-center gap-2"
    set :checkbox_class, "rounded border-[#d6dfd5] accent-[#1d4936]"
    set :checkbox_label_class, "text-sm text-[#415348]"
  end

  override Components.HorizontalRule do
    set :root_class, "relative my-6"
    set :hr_inner_class, "w-full border-t border-[#e5e9e3]"
    set :text_inner_class, "bg-white px-3 text-sm text-[#8a998e]"
  end

  override Components.MagicLink do
    set :root_class, "mt-5"
    set :label_class, @heading_class
  end

  override Components.MagicLink.Input do
    set :submit_class, @button_class
    set :remember_me_class, "mt-4 flex items-center gap-2"
    set :checkbox_class, "rounded border-[#d6dfd5] accent-[#1d4936]"
    set :checkbox_label_class, "text-sm text-[#415348]"
  end

  override Components.Confirm.Input do
    set :submit_class, @button_class
  end

  override Components.SignOut do
    set :root_class, @card_class
    set :h2_class, "text-2xl font-semibold tracking-tight text-[#1d4936]"
    set :info_text_class, "mt-3 text-sm leading-6 text-[#68766b]"
    set :button_class, @button_class
  end
end
