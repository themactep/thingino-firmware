Send 2 Telegram
===============

"Send 2 Telegram" is a Thingino module that allows you to send snapshots
and short video clips from the camera to a Telegram channel or a group.

To set up the module, you need to follow these steps:

### Create a Telegram Bot

If you don't have a Telegram bot yet, you can create one by talking to the
[BotFather](https://t.me/botfather) on Telegram.

The BotFather will give you a token that you will use to authenticate your bot.
The token looks like a long string of characters:

```
123456789:ABCdefGhIJKlmnoPQRstuVWXyz1234567890
```

Fill that information in the `Telegram Bot Token` field of the `send2telegram`
module configuration form.

> [!WARNING]
> Do not share the token with anyone!
> Token is a secret key that allows access to your bot.

### Get your chat ID

You can get your chat ID by sending a random message to your chat.
Right click on the message and select "Copy message link". The link will look
like this:

```
https://t.me/c/<CHAT_ID>/<MESSAGE_ID>
```

Use the `<CHAT_ID>` part of the link as your chat ID prefixing it with `-100`.
For example, if your chat ID is `123456789`, you should use `-100123456789`.
Fill that information in the `Chat ID` field of the `send2telegram` module
configuration form.

### Set the Telegram Bot as an administrator

You need to set the Telegram bot as an administrator of your channel or group
to allow it to send messages. To do this, go to your channel or group settings
and add the bot as an administrator. You can do this by searching for the bot
by its username (the one you set when creating the bot) and selecting it from
the list. Make sure to give it permission to send messages.

### Set up the caption for the message

You can set up the caption for the message that will be sent to the Telegram
channel or group. You can use the following placeholders in the caption:
- `%hostname` - The hostname of the Thingino device
- `%datetime` - The date and time when the message was sent.

### Select the type of message to send

You can select the type of message to send. Choose between:
- `Snapshot` - Send a snapshot from the camera.
- `Video` - Send a short video clip from the camera.

### Test the configuration

Once you have filled in all the required fields, you can test the configuration
by clicking on the "Send to Telegram" button on the preview page.
This will send a message to your Telegram channel or group. If everything
is set up correctly, you should see the message in your Telegram chat shortly.
