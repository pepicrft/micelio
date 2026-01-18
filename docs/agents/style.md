# Code Style & Conventions

## Elixir

### Syntax

- Lists **do not support index access**: Use `Enum.at/2`, pattern matching, or `List` functions
- Variables are immutable but can be rebound; block expressions (`if`, `case`, `cond`) must bind results:

```elixir
# Wrong
if connected?(socket) do
  socket = assign(socket, :val, val)
end

# Right
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  else
    socket
  end
```

- **Never** nest multiple modules in the same file
- **Never** use map access (`changeset[:field]`) on structs; use `struct.field` or `Ecto.Changeset.get_field/2`
- Use standard library for dates: `Time`, `Date`, `DateTime`, `Calendar`
- Don't use `String.to_atom/1` on user input
- Predicate functions end with `?` (not `is_`)
- Place `require` at module root, never inside functions
- Use `Task.async_stream/3` with `timeout: :infinity` for concurrent enumeration

### Mix

- Read docs with `mix help task_name` before using tasks
- **Avoid** `mix deps.clean --all` unless necessary

## Ecto

- **Never** use `@type` annotations in Ecto schema modules
- **Never** use section divider comments like `# ====` in context modules
- **Always** preload associations when accessed in templates
- `Ecto.Schema` fields use `:string` type even for `:text` columns
- `validate_number/2` does not support `:allow_nil`
- Fields set programmatically (like `user_id`) must not be in `cast` calls
- **Always** use `mix ecto.gen.migration name` for migrations

## Phoenix

- Router `scope` blocks include an optional alias prefixed for all routes
- Don't create aliases for route definitions; scope provides them
- Don't use `Phoenix.View`

## HEEx Templates

- **Always** use `~H` or `.html.heex` files
- Use `Phoenix.Component.form/1` and `to_form/2`, not `Phoenix.HTML.form_for`
- Add unique DOM IDs to key elements for testing
- **Never** use `else if` or `elsif`; use `cond` or `case`
- For literal curly braces in code blocks, use `phx-no-curly-interpolation`:

```heex
<code phx-no-curly-interpolation>
  let obj = {key: "val"}
</code>
```

- Class attributes support lists with conditionals:

```heex
<a class={[
  "px-2 text-white",
  @flag && "py-5",
  if(@condition, do: "border-red", else: "border-blue")
]}>
```

- **Never** use `<% Enum.each %>`; use `<%= for item <- @collection do %>`
- Use `<%!-- comment --%>` for HEEx comments
- Use `{...}` for attribute interpolation, `<%= %>` only within tag bodies

## LiveView

- Use `<.link navigate={}>` and `<.link patch={}>`, not deprecated `live_redirect`/`live_patch`
- **Avoid** LiveComponents unless specifically needed
- Name LiveViews with `Live` suffix: `AppWeb.WeatherLive`

### Streams

**Always** use streams for collections:

```elixir
stream(socket, :messages, [msg])           # append
stream(socket, :messages, [msg], at: -1)   # prepend
stream(socket, :messages, msgs, reset: true) # reset
stream_delete(socket, :messages, msg)      # delete
```

Template:

```heex
<div id="messages" phx-update="stream">
  <div :for={{id, msg} <- @streams.messages} id={id}>
    {msg.text}
  </div>
</div>
```

Streams are not enumerable. To filter, refetch and reset:

```elixir
messages = list_messages(filter)
stream(socket, :messages, messages, reset: true)
```

### Forms

```elixir
# In LiveView
socket = assign(socket, form: to_form(changeset))

# In template
<.form for={@form} id="my-form" phx-submit="save">
  <.input field={@form[:field]} type="text" />
</.form>
```

**Never** access `@changeset` in templates; always use `@form`.

### JavaScript Interop

For `phx-hook`, always set `phx-update="ignore"` if the hook manages its own DOM, and provide a unique DOM ID.

**Colocated hooks** (names start with `.`):

```heex
<input id="phone" phx-hook=".PhoneNumber" />
<script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
  export default {
    mounted() { /* ... */ }
  }
</script>
```

**External hooks** go in `assets/js/` and are passed to `LiveSocket`.

## CSS

- **Never** use Tailwind CSS classes
- Use vanilla modern CSS only
- Keep UI minimal like [SourceHut](https://sourcehut.org)
- **No emojis** in UI or content

### Theme-UI Variables

All styling uses CSS variables following [theme-ui spec](https://theme-ui.com/theme-spec):

- Design tokens: `assets/css/theme/tokens.css`
- Naming: `--theme-ui-<category>-<value>`
- Colors: `var(--theme-ui-colors-primary)`
- Spacing: `var(--theme-ui-space-2)`
- Typography: `var(--theme-ui-fonts-body)`, `var(--theme-ui-fontSizes-body)`

Page styles go in `assets/css/routes/<page>.css`.
