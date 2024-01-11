# gdMail

Deprecated. This has been merged into the engine as the new smtp module. See: https://github.com/Relintai/pandemonium_engine/tree/master/modules/smtp .

Pandemonium Engine addon to send emails through an SMTP server in a non-blocking way.

Should be relatively trivial to make it work on godot 3.x.

### Signals
- `result(Dictionary: { success: bool, error: Dictionary })`
- `email_sent()`
- `error(Dictionary: { error: String, code: int })`
