# Phone (Pocket Meter)

Pocket Meter is the Android home-screen widget, in [`android/`](../android/). It shows whichever
meters you mark `phone: true` in AI Meter's config, and it's updated by push, not polling: no
persistent notification, no VPN, no always-on connection. Android just wakes the app when a message
arrives.

It's fed over Firebase Cloud Messaging (FCM), against **your own** Firebase project: nobody else's
build of the app can send to it, and nothing about your usage goes through anyone's server but
Google's and the providers'.

This is optional and more involved than the desktop widget. You'll need a free Google account and
about fifteen minutes.

## 1. Create a Firebase project

```bash
firebase projects:create
```

Follow the prompt (pick any project ID; it doesn't need to match anything). Note the project ID:
you'll use it below as `your-project-id`.

## 2. Register the Android app

```bash
firebase apps:create ANDROID --package-name org.mat.pocketmeter --project your-project-id
```

Download its config file and put it where the Android build expects it:

```bash
firebase apps:sdkconfig ANDROID <app-id-from-the-previous-step> --project your-project-id \
  --out android/app/google-services.json
```

(Or download it from the Firebase console: Project settings → Your apps → `google-services.json`.)

## 3. Enable the FCM API

In the [Google Cloud console](https://console.cloud.google.com/apis/library/fcm.googleapis.com) for
`your-project-id`, enable the **Firebase Cloud Messaging API**.

## 4. Create a service account for sending

```bash
gcloud iam service-accounts create ai-meter-push --project your-project-id
gcloud projects add-iam-policy-binding your-project-id \
  --member="serviceAccount:ai-meter-push@your-project-id.iam.gserviceaccount.com" \
  --role="roles/firebasecloudmessaging.admin"
gcloud iam service-accounts keys create ~/.config/ai-meter/fcm-service-account.json \
  --iam-account="ai-meter-push@your-project-id.iam.gserviceaccount.com"
chmod 600 ~/.config/ai-meter/fcm-service-account.json
```

That key is what `ai-meter push` uses to sign the FCM send request. Keep it out of version control
(it already is: see `.gitignore`).

## 5. Write push.json

```bash
cat > ~/.config/ai-meter/push.json <<'EOF'
{
  "projectId": "your-project-id",
  "serviceAccount": "~/.config/ai-meter/fcm-service-account.json",
  "topic": "meters"
}
EOF
chmod 600 ~/.config/ai-meter/push.json
```

Full field reference: [`contract.md`](contract.md#pushjson-and-the-fcm-message).

### Why a plain topic name is safe

FCM topics aren't secret by themselves, but sending to one requires the service account key from
step 4: and that key only exists in your Firebase project. Nobody else's app build can send to
your topic, because nobody else has that key. Pick any topic name; `meters` is fine.

## 6. Build the APK

You need a JDK (17 or 21) on `JAVA_HOME`:

```bash
cd android
JAVA_HOME=/path/to/jdk-17 ./gradlew assembleDebug
```

Optionally override the topic the app subscribes to at build time (defaults to `meters`, matching
`push.json` above):

```bash
JAVA_HOME=/path/to/jdk-17 ./gradlew assembleDebug -PaiMeterTopic=meters
```

The APK lands at `android/app/build/outputs/apk/debug/app-debug.apk`.

## 7. Install and enable

Install the APK on your phone (`adb install app-debug.apk`, or copy it over and open it), then
**open the app once**: that's what subscribes the device to the FCM topic. Widgets on Android only
receive messages for topics the app has actively subscribed to.

Add the "Pocket Meter" widget to your home screen (long-press home screen → Widgets → Pocket
Meter).

Back on the desktop, enable the push timer if `install.sh` didn't already (it only enables it when
`push.json` exists):

```bash
systemctl --user enable --now ai-meter-push.timer
```

## 8. Test it

```bash
ai-meter push --force
```

Check `journalctl --user -u ai-meter-push.service` for the one-line status
(`push: sent (forced)` / `push: skipped (unchanged)` / an error), and the widget on your phone
should refresh within a few seconds.

## Troubleshooting

- **Widget never updates**: reopen the app once (re-subscribes to the topic), then re-run
  `ai-meter push --force`.
- **`push: error obtaining FCM access token`**: check `serviceAccount` in `push.json` points at a
  readable file, and that the service account still has the `firebasecloudmessaging.admin` role.
- **`push: error payload too large`**: you have more `phone: true` meters than fit under 3.5 KB,
  turn a few off in **Configure → Meters**.
- **Nothing in `journalctl`**: confirm the timer is active with
  `systemctl --user list-timers ai-meter-push.timer`.
