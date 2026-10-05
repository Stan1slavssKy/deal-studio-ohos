# Walking every intent the phone has

`docs/demo-prompts.md` holds the three prompts this tool is demonstrated with.
This is the other thing: a worklist. 640 of the 810 intents installed on the
test phone are reachable through `insightIntentDriver.execute` as VERA calls it,
and exactly seven of them are described in `VeraIntentCatalog.ets`. Nothing says
what the other 633 do. A result code of 0 is chosen by the target's developer,
so the only evidence is a screen.

These prompts exist to produce that evidence. Run one, tap everything the
generated program offers, and fill in its table. A row with a real observation
in the last column is the material a catalogue row is written from
(`docs/intents-design.md` §7); a row that says "answered 0, nothing happened" is
worth just as much, because it closes the question.

## Two things to know before running any of this

**Nothing asks you first.** `ASK_BEFORE_CALLS` is `false`
(`entry/src/main/ets/components/VeraPreview.ets`), so the consent sheet is built
but switched off, and a tap goes straight to the phone. Prompts 18 to 26 reach
`SendTextMessage`, `CallMeeTime`, `RequestPayment`, `SendRedPacket`,
`DeleteContact`, `AddBlockList`, `SetCallForwardingOff` and the
parental-control family. On a phone with a real account, a real SIM and real
contacts, those can move money, message people and change what a child's phone
allows. Run them on a test device, or switch the consent flag on first.

**Maps and Music need a Huawei ID.** Without one they fail on authorization
before reaching anything worth recording (`VeraIntentCatalog.ets`, the comment
on `startNavigate`).

## How the wording was arrived at, and why it matters

A prompt does not see the registry. It sees what `describeTargetsForPrompt`
(`entry/src/main/ets/vera/VeraIntentRegistry.ets`) lets through: at most four
addresses from Jev, then everything whose `intentName` or bundle contains a word
of the request four characters or longer, ranked by how many, cut off at 2000
characters — about twenty addresses. So the words of a prompt decide what the
model is even able to reach, and a prompt written by feel does not work.

Five things learned by checking every prompt below against
`tools/prompt-coverage.py`, which reads this file and reimplements that budget:

**An expensive word spends the whole prompt.** `setting` occurs in 270 of the 640
names, `switch` in 90, `page` in 79, `call` in 44, `mode` in 30, `view` in about
30. One of them in a request fills the budget with whatever sorts first and crowds
out the cluster the prompt was written for. `tools/prompt-coverage.py --word page`
says what a word costs before you spend it, and that is the single most useful
thing in the tool.

**A word under four characters is free.** The selector skips it. So `set`, `get`,
`add`, `put` and `see` cost nothing, while `sets` matches 46 addresses and `opens`
matches 36 — the plain verb is both better English and cheaper. The same rule
makes four addresses unreachable altogether; see the end of this file.

**An inflection matches nothing.** "a button that starts recording" reaches
neither `StartRecord` nor `PauseRecord`, because `recording` is not a substring of
either. `forbidden` misses `Forbid`, `merged` misses `Merge`, `managing` misses
`Manage`, `recognises` misses `Recognize`. The stem as the intent spells it is the
only thing that works, which is why a few clauses below are deliberately
ungrammatical.

**A fragment matches the wrong app.** A wallpaper prompt ending "a line showing
what **came** back" spent three slots on `com.huawei.hmos.camera`, because `came`
is a substring of `camera`. `line` does the same to `BestSelectionPipeline`, `pass`
to three password intents, and `came`'s cousin `card` to the SIM manager.

**A repeated word counts again.** The score is a sum over the words of the
request, so saying `mode` eleven times gives every address containing it eleven
points. That is the only lever for lifting one address above another that matches
the same word, and prompts 35, 41 and 56 use it deliberately.

And one structural finding that shaped the set more than any of the above: **ties
break on the target string**, so `com.ohos.sceneboard` loses every tie to
`com.huawei.*`, and `com.huawei.hmos.vassistant` loses to every other
`com.huawei.*` bundle. A torch prompt that also mentioned single-hand mode and
screen orientation filled all twenty slots and `OpenFlashlight` never appeared at
all. Two of the splits below — prompts 1 and 2, 43 and 44 — exist only because of
that.

Reword and check; do not guess. The totals are at the end.

Each prompt is a plain description of an app. None of them mentions `intent`, a
bundle name or a parameter — the same rule `demo-prompts.md` states, and the
reason a hallucinated address fails at generation rather than on the phone.

---

## 1. Torch

The cheapest possible test of `intent.call`: two addresses, no parameters, and
an observable nobody can argue with.

```
Torch: one button for the flashlight and one to put it out, with the answer
under them.
```

Exercises `intent.call` with an empty parameter array, in the launcher rather
than in an app — `com.ohos.sceneboard` owns the torch, which is why a prompt
about the camera finds nothing.

**What to check.** The torch lights up. If the answer says `ok` and the room
stays dark, that is the failure mode this whole file exists to catch.

| intent | answer | what happened on screen |
|---|---|---|
| `sceneboard/OpenFlashlight` | | |
| `sceneboard/CloseFlashlight` | | |

## 2. One hand

```
One hand: a toggle for single handed use, buttons for the orientation, a slider
for the immersive level, and a button for the split.
```

Exercises the rest of the launcher's own controls, all parameterless except the
immersive level.

**What to check.** Single hand use shrinks the picture visibly; the orientation
buttons are checked by turning the phone over. `SetImmersiveLevel` takes a level
nobody has published, so expect it to answer and do nothing.

| intent | answer | what happened on screen |
|---|---|---|
| `sceneboard/EntrySingleHandMode` | | |
| `sceneboard/TurnOnSingleHandMode` | | |
| `sceneboard/TurnOffSingleHandMode` | | |
| `sceneboard/ExitSingleHandMode` | | |
| `sceneboard/LockScreenOrientation` | | |
| `sceneboard/UnlockScreenOrientation` | | |
| `sceneboard/SetImmersiveLevel` | | |
| `sceneboard/EntryImmersiveLightPage` | | |
| `sceneboard/ViewSplitScreen` | | |

## 3. Notification triage

Described by what it is for rather than by listing the six things it toggles.
One word, `notify`, reaches all thirteen addresses; naming banner, ringing,
vibrate and the rest as well would only add ties for them to lose.

```
Triage: I name an app and the program tells me every way that app may notify
me, and lets me change each one.
```

Exercises the per-app notification family — thirteen addresses that all take an
app identifier nobody publishes, which makes this the clearest test of what
happens when the model has to invent a parameter name.

**What to check.** Settings → Notifications → that app, before and after. If
nothing there moves while every call answers `ok`, record exactly that: it is
the evidence these thirteen need a contract before they can enter the catalogue.

| intent | answer | what happened on screen |
|---|---|---|
| `sceneboard/GetAllowAppNotifySwitch` | | |
| `sceneboard/SetAllowAppNotifySwitch` | | |
| `sceneboard/GetAllowAppNotifyCategory` | | |
| `sceneboard/SetAllowAppNotifyCategory` | | |
| `sceneboard/GetAppNotifyCategoryType` | | |
| `sceneboard/GetAppNotifyDisplayOnBanner` | | |
| `sceneboard/SetAppNotifyDisplayOnBanner` | | |
| `sceneboard/GetAppNotifyWithRinging` | | |
| `sceneboard/SetAppNotifyWithRinging` | | |
| `sceneboard/GetAppNotifyWithVibrate` | | |
| `sceneboard/SetAppNotifyWithVibrate` | | |
| `sceneboard/GetAppNotifyDisplayOnIconMark` | | |
| `sceneboard/SetAppNotifyDisplayOnIconMark` | | |
| `sceneboard/GetAppNotifyDisplayOnTop` | | |
| `sceneboard/SetAppNotifyDisplayOnTop` | | |
| `sceneboard/GetAppNotifyDisplayOnLockScreen` | | |
| `sceneboard/SetAppNotifyDisplayOnLockScreen` | | |

## 4. Quieter

```
Quieter: buttons for notification aggregation and for the smart notification
service, each with what it is set to now.
```

Exercises the two notification switches that are global rather than per-app, and
the only ones in the family with an explicit on and off intent apiece.

**What to check.** Pull the notification shade down. Aggregation is visible
immediately — grouped, or not grouped.

| intent | answer | what happened on screen |
|---|---|---|
| `sceneboard/CheckAggregationNotification` | | |
| `sceneboard/TurnOnAggregationNotification` | | |
| `sceneboard/TurnOffAggregationNotification` | | |
| `sceneboard/CheckSmartNotificationService` | | |
| `sceneboard/TurnOnSmartNotificationService` | | |
| `sceneboard/TurnOffSmartNotificationService` | | |

## 5. What the launcher suggests

Split from prompt 4 because `recommend` and `style` lose every tie to the eight
addresses that carry the word `notification`.

```
What the launcher suggests: a button for the recommend feature and one for the
HMS style in the bar, each with what it is at now.
```

Exercises the last two launcher toggles, both with an explicit on and off intent.

**What to check.** The recommendation row in the launcher's own settings, and
the status bar's icons.

| intent | answer | what happened on screen |
|---|---|---|
| `sceneboard/GetRecommendSwitch` | | |
| `sceneboard/TurnOnRecommendSwitch` | | |
| `sceneboard/TurnOffRecommendSwitch` | | |
| `sceneboard/TurnOnStatusBarHmsStyle` | | |
| `sceneboard/TurnOffStatusBarHmsStyle` | | |

## 6. Wallpaper roulette

```
Wallpaper roulette: a button to see which theme I have, a button to put on a
theme, a button to put up a specific wallpaper, one that adds an art signature
to it, and one that hands the wallpaper to the theme editor.
```

Exercises the launcher's theming intents. Note the deliberate absence of the
word "came" — see the fourth finding above.

**What to check.** The home screen. This is the one cluster where a wrong
parameter is unmistakable, because a wallpaper either changed or it did not.

| intent | answer | what happened on screen |
|---|---|---|
| `sceneboard/QueryThemes` | | |
| `sceneboard/SetTheme` | | |
| `sceneboard/SetSpecificThemes` | | |
| `sceneboard/SetSpecificWallpaper` | | |
| `sceneboard/SetWallpaperAndArtSignature` | | |
| `sceneboard/SetWallpaperFromThemeEditor` | | |

## 7. Alarms

```
Alarms: let me add an alarm at an hour and minute I pick, change it, get rid of
it, see every alarm I have, and when one goes off, put it off for nine minutes
or silence it.
```

Exercises the Clock's alarm intents. `CreateAlarm` is the most promising row in
this whole file: a standard intent name, in a first-party app, for something a
person genuinely asks a program to do.

**What to check.** Open Clock. The alarm is there at the hour asked, or it is
not. `DelayAlarmRing` and `StopAlarmRing` mean nothing unless an alarm is
actually ringing, so set one a minute ahead and wait for it.

| intent | answer | what happened on screen |
|---|---|---|
| `clock/CreateAlarm` | | |
| `clock/ModifyAlarm` | | |
| `clock/DeleteAlarm` | | |
| `clock/SearchAlarm` | | |
| `clock/ViewAlarm` | | |
| `clock/QueryAlarmRing` | | |
| `clock/DelayAlarmRing` | | |
| `clock/StopAlarmRing` | | |

## 8. Kitchen timer

```
Kitchen timer: a timer for the minutes I give, with buttons to start it, pause
it, reset it, throw it away and see what remains — and beside it a stopwatch to
start, pause and reset.
```

Exercises the other half of the Clock. Split from the alarms because the two
together crowd each other out of the budget.

**What to check.** Clock's Timer and Stopwatch tabs. A running timer is the
easiest observable in this file after the torch.

| intent | answer | what happened on screen |
|---|---|---|
| `clock/CreateTimer` | | |
| `clock/StartTimer` | | |
| `clock/PauseTimer` | | |
| `clock/ResetTimer` | | |
| `clock/ModifyTimer` | | |
| `clock/DeleteTimer` | | |
| `clock/GetRemainTimer` | | |
| `clock/ViewTimer` | | |
| `clock/StartStopwatch` | | |
| `clock/PauseStopwatch` | | |
| `clock/ResetStopwatch` | | |
| `clock/ViewStopwatch` | | |

## 9. Note keeper

```
Note keeper: I type a title and some words, and buttons make a note of it,
change that note, see it again, pass it on and throw it away.
```

Exercises the Notepad. Seven intents, one app, and a result you can go and look
at — which makes this a good second prompt to run after the torch.

**What to check.** Open Notepad. A note with that title exists, with those
words, or it does not.

| intent | answer | what happened on screen |
|---|---|---|
| `notepad/CreateNote` | | |
| `notepad/ModifyNote` | | |
| `notepad/GetNote` | | |
| `notepad/ViewNote` | | |
| `notepad/ShareNote` | | |
| `notepad/DeleteNote` | | |
| `notepad/CallSummaryCreateNote` | | |

## 10. Voice memo

```
Voice memo: a button that has the recorder start, one to pause, one to resume
and one to end it, with what it answered above them.
```

Exercises the sound recorder, four parameterless intents that form a state
machine — the only cluster here where calling them out of order should visibly
fail.

**What to check.** Open Sound Recorder afterwards and look for the file. Then
try pause before record and write down the answer: a target that refuses an
impossible call is a target worth trusting.

| intent | answer | what happened on screen |
|---|---|---|
| `soundrecorder/StartRecord` | | |
| `soundrecorder/PauseRecord` | | |
| `soundrecorder/ResumeRecord` | | |
| `soundrecorder/EndRecord` | | |

## 11. Camera shortcut

```
Camera shortcut: a button that brings up the camera, a shutter button to take
one, and a button for a camera function I choose.
```

Exercises the Camera. `TakePhoto` is the interesting one — a shutter press from
a generated program is either refused outright or it is a real capability. Note
that the prompt says "take one" and never "photo": `photo` occurs in 37 of the
640 names and would hand the whole budget to the Gallery.

**What to check.** Gallery. A new picture with this minute's timestamp, or
nothing. `DoCameraFunction` takes a function name nobody publishes.

| intent | answer | what happened on screen |
|---|---|---|
| `camera/OpenCamera` | | |
| `camera/TakePhoto` | | |
| `camera/DoCameraFunction` | | |

## 12. Album shelf

```
Album shelf: a button that goes to an album I pick, one that asks which album I
have, and a box that runs a search on what I shot.
```

Exercises the Gallery's front door — the part of its 35 intents a person would
recognise as something to ask for.

**What to check.** Gallery opens on the album named, or on its own front page,
or not at all. The distinction matters: opening the app while ignoring the album
is the `ViewSearchPageLocal` failure again (`VeraIntentCatalog.ets`).

| intent | answer | what happened on screen |
|---|---|---|
| `photos/JumpAlbum` | | |
| `photos/JumpToAlbum` | | |
| `photos/QueryAlbum` | | |
| `photos/AlbumManagement` | | |
| `photos/AlbumManagementForeground` | | |
| `photos/PhotosSearch` | | |
| `photos/PhotoSearchExecutor` | | |
| `photos/AgentSearch` | | |
| `photos/ConstructSearchQuery` | | |

## 13. Best of a batch

Twenty-three of the Gallery's intents are not features at all: they are steps of
an on-device selection pipeline the assistant drives. They are here because they
are reachable, not because a person would ask for them.

```
Best of a batch: buttons to pick the best shot of a set, run a similarity
selection, run a negative filter, do reservoir sampling, balance a cover grid,
ask for the relation and the person reference, trigger a boomerang, and abort.
```

Exercises the photos pipeline. Expect most of these to refuse: they take
structured input from a caller that already holds photo URIs, which a VERA
program never does.

**What to check.** Mostly the answer string, unusually for this file. A refusal
carrying the target's own code is the useful outcome, because it shows the
pipeline validates its input where the notification family does not.

| intent | answer | what happened on screen |
|---|---|---|
| `photos/SelectBestPhoto` | | |
| `photos/BestSelectionPipeline` | | |
| `photos/BatchSimilaritySelection` | | |
| `photos/BatchNegativeSimilaritySelection` | | |
| `photos/BatchNegativeFilter` | | |
| `photos/ReservoirSampling` | | |
| `photos/CoverGridSelection` | | |
| `photos/EventBalancedSelection` | | |
| `photos/EventBalancedCoverGridSelection` | | |
| `photos/GetRelation` | | |
| `photos/GetPersonReference` | | |
| `photos/CheckPersonReference` | | |
| `photos/BoomerangEventTrigger` | | |

## 14. What the gallery knows about itself

```
What the gallery knows: a button for the gallery itself, then buttons that ask
for the front desk, the front form, the browser uri, the operation log, the
version, the applock, the loading part, an edit, and one for an agent.
```

Exercises the rest of the photos pipeline, split from prompt 13 for budget.

**What to check.** The answer, and the hilog line. `QueryOperationLog` is a
`read` intent over private data; if any of it reaches the program's own screen,
that contradicts the rule in `intents-design.md` §3 and is the most important
thing this prompt can find.

| intent | answer | what happened on screen |
|---|---|---|
| `photos/OpenGalleryPage` | | |
| `photos/GalleryAbort` | | |
| `photos/CheckFrontDesk` | | |
| `photos/GetFrontForm` | | |
| `photos/GetPhotoBrowserViewUri` | | |
| `photos/QueryOperationLog` | | |
| `photos/VersionCheck` | | |
| `photos/AppLock` | | |
| `photos/LoadingPage` | | |
| `photos/AgentJump` | | |
| `photos/AgentLinkTo` | | |
| `photos/EnterMediaEditUiExtension` | | |

## 15. Music

```
Music: put on music for this hour of the day, the music I name, preload it, save
it, change it, pass it on, and set what I hear in my ear monitor.
```

Exercises the only cluster with a checked catalogue row in it
(`intent.playMusicList`), which makes this the calibration prompt: if the model
reaches for the catalogue row here instead of `intent.call`, the instruction
"prefer a row from the checked list" is doing its job.

**What to check.** Sound. Then which route the program took —
`hdc shell hilog | grep VERA-INTENT` shows whether it used the row or an
address.

| intent | answer | what happened on screen |
|---|---|---|
| `music/PlayMusic` | | |
| `music/PlayMusicList` | | |
| `music/PreloadMusic` | | |
| `music/SaveMusicList` | | |
| `music/RemoveMusic` | | |
| `vassistant/PlayMusic` | | |
| `vassistant/DownloadMusic` | | |
| `vassistant/EditMusic` | | |
| `vassistant/ShareMusic` | | |
| `mediacontroller/SetEarMonitorMode` | | |
| `mediacontroller/SetEarMonitorReverbMode` | | |

## 16. Reading and watching

```
Reading and watching: buttons for a book, an audio book, a video to watch and a
video to save.
```

Exercises the media apps' shared vocabulary. `OpenDownloadPage` and
`ViewDownloadedContent` exist four times over — Books, Movies, Games and Music —
which makes this the test of whether the model picks the right one of four
identical names.

**What to check.** Which app came to the front. A program that opens Music when
asked about books picked the wrong address, and that is worth knowing about the
prompt as much as about the intent.

| intent | answer | what happened on screen |
|---|---|---|
| `books/ReadBook` | | |
| `books/ReadRecommendBook` | | |
| `books/PlayAudio` | | |
| `himovie/PlayVideo` | | |
| `himovie/SaveVideoList` | | |

## 17. Getting there

```
Getting there: a box where I put a place, then buttons to navigate to it, see
the route, keep the location, search for it, hail a taxi, and pick the taxi app
or the navigate app that does it.
```

Exercises maps and taxi, including the two rows already in the catalogue
(`startNavigate`, `searchOnMap`) and the two apps that both declare
`StartNavigate` — Petal Maps and AMap.

**What to check.** A route on screen to the right place. `searchOnMap` is known
to answer 0 and ignore the query, so the query being honoured here would be
news. `ViewCalendarEvent` refused an empty payload with its own code `10020012`.

| intent | answer | what happened on screen |
|---|---|---|
| `app/StartNavigate` | | |
| `app/ViewRoutes` | | |
| `app/MarkingLocations` | | |
| `app/ViewSearchPageLocal` | | |
| `hmapp/StartNavigate` | | |
| `hmapp/StartTaxi` | | |
| `vassistant/NavigateAppSelector` | | |
| `vassistant/TaxiAppSelector` | | |

## 18. Contacts

**Critical.** `DeleteContact` deletes a contact, with nothing between the tap
and the deletion.

```
Contacts: a box to look through my contacts, a button to add one from a name I
type, a button to get rid of one, and a look at who called me and who I missed.
```

Exercises Contacts. `AddContact` and `DeleteContact` are a matched pair worth
probing together: if the add works and the delete does not, the parameter shape
differs between them and the catalogue needs two rows, not one.

**What to check.** The Contacts app. Add first, confirm it appeared, then delete
that one and confirm it went — never a contact you care about.

| intent | answer | what happened on screen |
|---|---|---|
| `contacts/SearchContacts` | | |
| `contacts/AddContact` | | |
| `contacts/DeleteContact` | | |
| `contacts/QueryCallLog` | | |
| `contacts/CheckMissedCall` | | |
| `contacts/OpenBatchDeleteCallLogPage` | | |
| `contacts/JumpMyCardSettingsPage` | | |
| `contacts/ContactsSettingSwitch` | | |

## 19. Reaching someone over MeeTime

**Critical.** These send messages and place calls to whoever the model put in
the parameters.

```
Reaching someone over MeeTime: find my MeeTime devices, check whether MeeTime
works here, and buttons that send someone a message, my location or a file over
MeeTime.
```

Exercises MeeTime. The four `Send*` intents are the clearest case in
`intents-design.md` §3 of the model writing a recipient: a name it guessed,
presented as fact.

**What to check.** Your own second device, or a number you own. Check *who*
received it, not only that something was sent — a message to the wrong recipient
answers `ok` exactly like a message to the right one.

| intent | answer | what happened on screen |
|---|---|---|
| `meetimeservice/SearchMeeTimeDevices` | | |
| `meetimeservice/BatchSearchMeeTimeDevices` | | |
| `meetimeservice/CheckMeeTimeFunction` | | |
| `meetimeservice/CheckRemoteMessageCap` | | |
| `meetimeservice/CallMeeTime` | | |
| `meetimeservice/SendTextMessage` | | |
| `meetimeservice/SendLocationMessage` | | |
| `meetimeservice/SendFileMessage` | | |
| `meetimeservice/SendPhotoMessage` | | |
| `vassistant/SendMessage` | | |

## 20. Money

**Critical, and the one to think twice about.** `RequestPayment` and
`SendRedPacket` move money, and the amount and the recipient are written by the
model. Section 9 of `intents-design.md` asks whether this class should be
allowed at all; this prompt is how that question gets an answer rather than an
opinion.

```
Money: a button that asks for a payment, one that sends a red packet, one that
brings up the cashier, buttons for my subway — see it, add one, put money on it
— and one for public transport.
```

Exercises the payment and wallet family, every row of it `critical` by §4.

**What to check.** Whether a confirmation screen appears *from the target app*.
That is the real finding here: if Wallet and Payment put their own dialog in
front of the money, the risk class is about what reaches the target rather than
about what it does. If they do not, `critical` needs the consent sheet switched
on before this set is run again.

| intent | answer | what happened on screen |
|---|---|---|
| `payment/RequestPayment` | | |
| `payment/SendRedPacket` | | |
| `vassistant/OpenCashierPage` | | |
| `vassistant/CashierPicker` | | |
| `wallet/ViewSubwayCard` | | |
| `wallet/AddSubwayCard` | | |
| `wallet/RechargeSubwayCard` | | |
| `wallet/TriggerPublicTransportation` | | |

## 21. Call handling

**Critical** in one row: `SetCallForwardingOff` turns forwarding off silently,
which is how calls get missed.

```
Call handling: show and change flip to mute, pick up to reduce the sound and
quick calling, with a button beside each that goes there; then forwarding — ask
what it is and turn it off — plus the auto answer, the auto summary and the call
assistance.
```

Exercises the call settings. These are first-party toggles with named intents,
so this is the cluster where a `Set*` intent has the best chance of really
working.

**What to check.** Settings → Call. Each toggle, before and after. Note that
`GetImsSwitch`, `CheckImsSwitch` and `SetImsSwitch` cannot be reached
lexically at all — `ims` is three characters, so the selector skips it, and only
Jev can put them in the prompt. If they are absent from the generated program,
that is the reason.

| intent | answer | what happened on screen |
|---|---|---|
| `callsetting/GetFlipMuteSwitch` | | |
| `callsetting/SetFlipMuteSwitch` | | |
| `callsetting/JumpToFlipMuteSetting` | | |
| `callsetting/GetPickUpReduceVolumeSwitch` | | |
| `callsetting/SetPickUpReduceVolumeSwitch` | | |
| `callsetting/JumpToPickUpReduceVolumeSetting` | | |
| `callsetting/GetQuickCallSwitch` | | |
| `callsetting/SetQuickCallSwitch` | | |
| `callsetting/JumpToQuickCallSetting` | | |
| `callsetting/QueryCallForwarding` | | |
| `callsetting/SetCallForwardingOff` | | |
| `callsetting/JumpToCallForwarding` | | |
| `vassistant/SetAutoAnswerConfig` | | |
| `vassistant/SetCallAssistance` | | |
| `vassistant/CallAutoSummaryConfig` | | |

## 22. Recorded calls

```
Recorded calls: whether the recorder is on, whether it should merge what it
records, which callers get recorded, a button to add one, one to take one off and
one to clear them all.
```

Exercises the call-recording intents, split out of prompt 21 because the two
together overflow the budget. `DeleteAllCallRecordNumbers` is `critical`.

**What to check.** Settings → Call → Call recording. The list of numbers is the
observable; adding one and watching it appear is the proof that
`AddCallRecordNumber` takes the parameter it looks like it takes.

| intent | answer | what happened on screen |
|---|---|---|
| `callsetting/GetCallRecordSwitch` | | |
| `callsetting/SetCallRecordSwitch` | | |
| `callsetting/SetCallRecordMergeSetting` | | |
| `callsetting/GetCallRecordNumbers` | | |
| `callsetting/AddCallRecordNumber` | | |
| `callsetting/DeleteCallRecordNumber` | | |
| `callsetting/DeleteAllCallRecordNumbers` | | |

## 23. Blocked and trusted

**Critical.** These change who can reach the phone, and wipe records that cannot
be recovered.

```
Blocked and trusted: a box for a number, buttons to block it, to trust it, to
stop blocking it and to stop trusting it, and two that wipe what was blocked.
```

Exercises the spam shield. Six addresses, all `critical` by §4, and all about
other people reaching you.

**What to check.** Phone → Blocked. The number is listed after the add and gone
after the remove. Wiping the records cannot be undone, so do that last.

| intent | answer | what happened on screen |
|---|---|---|
| `spamshield/AddBlockList` | | |
| `spamshield/RemoveFromBlockList` | | |
| `spamshield/AddTrustList` | | |
| `spamshield/RemoveFromTrustList` | | |
| `spamshield/ClearCallBlockRecords` | | |
| `spamshield/ClearSmsBlockRecords` | | |

## 24. How long an app was used

```
How long an app was used: its usage today, its usage in the last seven days, the
one I am in most today, the one I am in most in seven days, whether healthy use
is on and whether that is behind a password, and what the password is.
```

Exercises the reading half of the parental-control family: nine intents that
return private data, which is why `runIntent` gives a program only a status and
never the payload.

**What to check.** Compare with Settings → Digital Balance. And check what the
program was told: if a usage figure reaches the screen, the "read results never
reach the program" rule has a hole in it.

| intent | answer | what happened on screen |
|---|---|---|
| `parentcontrol/GetAppDailyUsage` | | |
| `parentcontrol/GetAppLastSevenDayUsage` | | |
| `parentcontrol/GetDailyMostUsage` | | |
| `parentcontrol/GetLastSevenDayMostUsage` | | |
| `parentcontrol/GetLastSevenDayTotalUsage` | | |
| `parentcontrol/GetSpecifiedAppUsage` | | |
| `parentcontrol/GetSpecifiedTotalUsage` | | |
| `parentcontrol/GetHealthyUseStatus` | | |
| `parentcontrol/IsHealthUsePhoneSetPassword` | | |

## 25. Allowed, forbidden, limited

**Critical.** Fifteen intents that decide what somebody else's phone will do,
and a generated program can call any of them. Nothing on the phone marks them as
privileged: `EXECUTE_INSIGHT_INTENT` is unscoped, so they sit at exactly the
same distance from a program as the torch does.

```
Allowed and forbid: which app is always permitted, which I forbid and which has
a limit, with buttons to set each for one app or for all, and buttons to wipe
each.
```

Exercises the writing half of parental control.

**What to check.** Settings → Digital Balance, with a password set on it. The
question that matters is whether a set password blocks these calls. If it does
not, that belongs in `intents-design.md` §9 as an argument for forbidding
`critical` outright.

| intent | answer | what happened on screen |
|---|---|---|
| `parentcontrol/GetAppsAlwaysAllowUsed` | | |
| `parentcontrol/SetAppsAlwaysAllowUsed` | | |
| `parentcontrol/SetAllAppAlwaysAllowUsed` | | |
| `parentcontrol/DeleteAppsAlwaysAllowUsed` | | |
| `parentcontrol/DeleteAllAppAlwaysAllowUsed` | | |
| `parentcontrol/GetAppsForbidUse` | | |
| `parentcontrol/SetAppsForbidUse` | | |
| `parentcontrol/SetAllAppForbidUsed` | | |
| `parentcontrol/DeleteAppsForbidUse` | | |
| `parentcontrol/DeleteAllAppForbidUsed` | | |
| `parentcontrol/GetAppsLimitTime` | | |
| `parentcontrol/SetAppsLimitTime` | | |
| `parentcontrol/SetAllAppLimitTime` | | |
| `parentcontrol/DeleteAppsLimitTime` | | |
| `parentcontrol/DeleteAllAppLimitTime` | | |

## 26. Use periods and away time

**Critical**, for the same reason as prompt 25.

```
Use periods: a toggle to manage use, a button to add a period of use, a button
to add a suspension, a button to wipe the away hours and one to wipe the total,
and a button to close healthy use.
```

Exercises the period half of parental control, split from prompt 25 for budget.

**What to check.** Settings → Digital Balance → the schedule. A period that
appears there is the strongest single result in this whole cluster, because it
means the parameter shape was guessed right.

| intent | answer | what happened on screen |
|---|---|---|
| `parentcontrol/GetScreenUseTimeManageSwitch` | | |
| `parentcontrol/SetScreenUseTimeManageSwitch` | | |
| `parentcontrol/AddScreenUsePhoneUsePeriod` | | |
| `parentcontrol/GetScreenUsePhoneUsePeriod` | | |
| `parentcontrol/AddScreenUseSuspensionPeriod` | | |
| `parentcontrol/GetScreenUseSuspensionPeriod` | | |
| `parentcontrol/DeleteAwayTime` | | |
| `parentcontrol/DeleteTotalTime` | | |
| `parentcontrol/CloseHealthUsePhone` | | |

## 27. Privacy

```
Privacy: which app has which permission, which app used a permission and when,
a button to change an app's permission, and the camera and location toggles.
```

Exercises the privacy centre. Seven of these are `read` intents over private
data, and `SetAppAccessPermissions` writes it.

**What to check.** Settings → Privacy → Permission manager. And note what the
program itself was told: a permission record reaching the screen would be the
same hole prompt 24 looks for.

`GetMicSettingSwicth` and `SetMicSettingSwicth` cannot be reached lexically —
`mic` is three characters, so the selector skips it — and the firmware spells
both of them `Swicth`, so `switch` does not match either. Only Jev can put them
in a prompt.

| intent | answer | what happened on screen |
|---|---|---|
| `privacycenter/GetAppAccessPermissions` | | |
| `privacycenter/SetAppAccessPermissions` | | |
| `privacycenter/GetAccessSpecifiedPermissionApps` | | |
| `privacycenter/GetAllPermissionsesUsedByApp` | | |
| `privacycenter/GetAppAllPermissionsRecords` | | |
| `privacycenter/GetAppSpecifiedPermissionRecord` | | |
| `privacycenter/GetSpecifiedPermissionAllRecords` | | |
| `privacycenter/GetCameraSettingSwicth` | | |
| `privacycenter/SetCameraSettingSwicth` | | |
| `privacycenter/GetLocationSettingSwicth` | | |
| `privacycenter/SetLocationSettingSwicth` | | |

## 28. Battery

```
Battery: how long the battery has left, buttons to extend the battery, customise
the battery and reset it, then which app drains the most power, the power an app
spent, whether performance is capped with a toggle for performance, and the
scheduled power with a button to go there.
```

Exercises battery care and the power readings in Settings.

**What to check.** Settings → Battery. `ExtendBatteryLife` is the one worth
watching: if it moves the estimate on that screen, it is a real row.

| intent | answer | what happened on screen |
|---|---|---|
| `batterycare/GetBatteryLife` | | |
| `batterycare/ExtendBatteryLife` | | |
| `batterycare/CustomizeBatteryLife` | | |
| `batterycare/ResetBatteryLife` | | |
| `settings/GetAppPowerConsumptionPercent` | | |
| `settings/GetAppPowerConsumptionRanking` | | |
| `settings/GetAppUsageDurationAndPower` | | |
| `settings/GetPerformanceModeSwitch` | | |
| `settings/SetPerformanceModeSwitch` | | |
| `settings/GetScheduledPowerStatus` | | |
| `settings/SetScheduledPower` | | |
| `settings/JumpScheduledPower` | | |

## 29. SIM cards

```
SIM cards: which simcard dials out by default, which simcard carries the mobile
data, the simcard number, the simcard toggle and whether it is on, and for a
simcard its network, its signal strength, its cell id, its mcc and mnc and its
sms centre.
```

Exercises the SIM management app and the six SIM readings Settings declares.
`simcard` as one word reaches all sixteen of them; `sim` on its own is three
characters and reaches nothing.

**What to check.** Settings → Mobile network → SIM cards, against what the
program reports.

| intent | answer | what happened on screen |
|---|---|---|
| `simcardmanagement/GetDefaultDialingSimCard` | | |
| `simcardmanagement/SetDefaultDialingSimCard` | | |
| `simcardmanagement/GetDefaultMobileDataSimCard` | | |
| `simcardmanagement/SetDefaultMobileDataSimCard` | | |
| `simcardmanagement/GetSimCardNumber` | | |
| `simcardmanagement/GetSimSwitch` | | |
| `simcardmanagement/SetSimSwitch` | | |
| `simcardmanagement/CheckSimSwitch` | | |
| `settings/GetSimCardNetwork` | | |
| `settings/GetSimCardMobileNetworkType` | | |
| `settings/GetSimCardSignalStrength` | | |
| `settings/GetSimCardCellId` | | |
| `settings/GetSimCardMccMnc` | | |
| `settings/GetSimCardSmsCenterNumber` | | |

## 30. Mobile data

```
Mobile data: the roaming toggle, whether roaming is on and a roaming check, plus
buttons for traffic management, a traffic ranking, more traffic and whether
traffic shows at all.
```

Exercises the traffic app, the roaming switches in the call settings and the two
network checks in the health service.

**What to check.** Settings → Mobile network → Data usage. Roaming is the one
that matters: a program that can turn roaming on can cost money abroad, which is
an argument for putting `SetDataRoamingSwitch` in the `critical` class rather
than in `act`.

| intent | answer | what happened on screen |
|---|---|---|
| `callsetting/GetDataRoamingSwitch` | | |
| `callsetting/SetDataRoamingSwitch` | | |
| `callsetting/CheckDataRoamingSwitch` | | |
| `communicationsetting/JumpToTrafficManagement` | | |
| `communicationsetting/JumpToTrafficRanking` | | |
| `communicationsetting/JumpToMoreTrafficSettings` | | |
| `communicationsetting/GetTrafficDisplaySwitch` | | |
| `communicationsetting/SetTrafficDisplaySwitch` | | |

## 31. Signal check

Split from prompt 30: each of these matches exactly one address, and a word that
matches one address loses every tie to `traffic`, which matches five.

```
Signal: a button for one app's network, one for wifi coming on by itself, one
that looks at my carrier and one that looks for a weak signal.
```

Exercises the four network readings that live outside the traffic app.

**What to check.** `SetWifiAutoEnable` is the only write here; Settings → Wi-Fi
shows whether it took.

| intent | answer | what happened on screen |
|---|---|---|
| `communicationsetting/OpenAppNetwork` | | |
| `settings/SetWifiAutoEnable` | | |
| `hiviewcare/DetectCarrier` | | |
| `hiviewcare/DetectWeakSignal` | | |

## 32. Things near me

```
Things near me: the bluetooth name, the bluetooth I am paired to and the other
bluetooth around, the paired sparklink and every sparklink, my hicar cars with
buttons to disconnect one, forget one and let hicar pair by itself, the things I
trust with a list of what I trust, and buttons for an external drive and for
another external one.
```

Exercises the device lists in Settings, HiCar and the Files app's external
storage.

**What to check.** Every one of these is a `read` except the three HiCar writes.
`DeleteHiCarDevice` unpairs a car; do that only with a car you can pair again.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/GetBluetoothDeviceName` | | |
| `settings/GetPairedBluetoothDevices` | | |
| `settings/GetOtherBluetoothDevices` | | |
| `settings/GetPairedSparkLinkDevices` | | |
| `settings/GetOtherSparkLinkDevices` | | |
| `hicar/GetHiCarDevices` | | |
| `hicar/DisconnectHiCarDevice` | | |
| `hicar/DeleteHiCarDevice` | | |
| `hicar/SetHiCarAutoConnectSwitch` | | |
| `slassistant/GetTrustDevices` | | |
| `files/OpenExternalDevice` | | |
| `files/OpenExternalDevice1` | | |
| `files/CloseExternalDevice` | | |

## 33. Sharing

The word `huawei` is unusable in a prompt: it is a substring of nearly every
bundle on the phone, so it matches almost all 640 addresses at once. `share`
reaches this whole cluster — and that is the difficulty, because twenty addresses
carry it and the budget holds twenty lines. Hence two prompts, each giving its own
rows a second word so they score two and the rest of the cluster scores one.

```
Sharing: the main share toggle, whether the main share is on, the share state it
detects, whether that state is on, a share page to open and whether that share
page is there.
```

Exercises the core of Huawei Share.

**What to check.** Settings → More connections → Huawei Share, before and after
each toggle.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/GetHuaweiShareMainSwitch` | | |
| `settings/SetHuaweiShareMainSwitch` | | |
| `settings/CheckHuaweiShareMainSwitch` | | |
| `settings/GetHuaweiShareDetectState` | | |
| `settings/SetHuaweiShareDetectState` | | |
| `settings/CheckHuaweiShareDetectState` | | |
| `settings/OpenHuaweiSharePage` | | |
| `settings/CheckHuaweiSharePage` | | |

## 34. Sharing a keyboard

```
Sharing a keyboard: the share permission and whether that permission is on, hand
eye share and whether hand eye share is on, and key mouse share with a button to
open key mouse share.
```

Exercises the rest of Huawei Share: the permission, and the two intents for
driving one machine from another.

**What to check.** Settings → More connections, the Key-mouse sharing row. This
one needs a second device to mean anything.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/GetHuaweiSharePermissionSwitch` | | |
| `settings/SetHuaweiSharePermissionSwitch` | | |
| `settings/CheckHuaweiSharePermissionSwitch` | | |
| `settings/GetHandEyeShare` | | |
| `settings/SetHandEyeShare` | | |
| `settings/CheckHandEyeShare` | | |
| `settings/GetKeyMouseShare` | | |
| `settings/SetKeyMouseShare` | | |
| `settings/OpenKeyMouseShare` | | |
| `settings/CheckKeyMouseShare` | | |

## 35. Carrying on elsewhere

```
Carrying on elsewhere: a toggle to continue, a button to continue on another one,
a way to continue later, whether continuation is on and what continuation covers,
the clipboard between my things, a clipboard button and what the clipboard holds,
super and the super hub, and interconnectivity with an interconnectivity button.
```

Exercises the cross-device half of Settings, split from prompts 33 and 34 because
none of these carries the word `share`.

**What to check.** Settings → More connections. A second HarmonyOS device makes
this cluster meaningful; without one, most of these read a switch and nothing
more.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/GetContinueSwitch` | | |
| `settings/SetContinueSwitch` | | |
| `settings/OpenContinueSwitchPage` | | |
| `settings/CheckContinuation` | | |
| `settings/GetCrossDeviceClipboard` | | |
| `settings/SetCrossDeviceClipboard` | | |
| `settings/OpenCrossDeviceClipboard` | | |
| `settings/CheckCrossDeviceClipboard` | | |
| `settings/GetSuperDevice` | | |
| `settings/SetSuperDevice` | | |
| `settings/OpenSuperDevicePage` | | |
| `settings/CheckSuperDevice` | | |
| `settings/GetDeviceInterconnectivity` | | |
| `settings/SetDeviceInterconnectivity` | | |
| `settings/OpenDeviceInterconnectivityPage` | | |
| `settings/CheckDeviceInterconnectivity` | | |

## 36. Seeing better

```
Seeing better: the magnification type, the zoom trigger, a button for bionic
vision, and buttons for picture display and picture enhance.
```

Exercises the vision half of accessibility. Note that `hdr` is three characters,
so the three HDR pages are reached through `display` and `enhance` instead.

**What to check.** Settings → Accessibility. Magnification is visible the moment
it changes.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/GetMagnificationType` | | |
| `settings/SetMagnificationType` | | |
| `settings/GetZoomGestureTrigger` | | |
| `settings/SetZoomGestureTrigger` | | |
| `settings/JumpBionicVisionPage` | | |
| `settings/JumpHdrPicDisplayPage` | | |
| `settings/JumpHdrPicEnhancePage` | | |
| `settings/JumpHdrVideoEnhancePage` | | |

## 37. Hearing better

```
Hearing better: the flash reminder toggle, its scene, whether the flash reminder
is on and a button for its page; then sound recognition — its toggle, whether it
is on, its page — and the sound type toggle.
```

Exercises the hearing half of accessibility. `flash` also reaches the torch, so
prompt 1 and this one overlap by two addresses on purpose: the same word, two
very different results.

**What to check.** Settings → Accessibility → Hearing. The flash reminder is
testable: turn it on and have someone call.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/GetFlashReminderSwitch` | | |
| `settings/SetFlashReminderSwitch` | | |
| `settings/CheckFlashReminderEnable` | | |
| `settings/GetFlashReminderScene` | | |
| `settings/SetFlashReminderScene` | | |
| `settings/JumpFlashReminderPage` | | |
| `settings/GetSoundRecognitionSwitch` | | |
| `settings/SetSoundRecognitionSwitch` | | |
| `settings/CheckSoundRecognitionEnable` | | |
| `settings/JumpSoundRecognitionPage` | | |
| `settings/GetSoundTypeSwitch` | | |
| `settings/SetSoundTypeSwitch` | | |

## 38. Screen reader

```
Screen reader: buttons to pause the reader, restore the reader, restore its
defaults and its gestures, reset its speed and its tone, take the reader volume
up, down, to maximum and to minimum, ask about the reader in a call, give it a
custom gesture or the system default, the recognition toggle with a button each
way, and the reader menu.
```

Exercises the screen reader, the one app whose whole intent surface is reachable
with a single word.

**What to check.** Turn the screen reader on in Settings → Accessibility first,
or every one of these has nothing to act on. Then listen: a speed reset and a
volume change are both audible.

| intent | answer | what happened on screen |
|---|---|---|
| `screenreader/PauseScreenReading` | | |
| `screenreader/RestoreScreenReading` | | |
| `screenreader/RestoreScreenReadingDefaults` | | |
| `screenreader/RestoreScreenReadingGestures` | | |
| `screenreader/ResetScreenReadingSpeed` | | |
| `screenreader/ResetScreenReadingTone` | | |
| `screenreader/GetAudioVolumeSeekBar` | | |
| `screenreader/TurnAudioVolumeSeekBar` | | |
| `screenreader/TurnUpAudioVolumeSeekBar` | | |
| `screenreader/TurnDownAudioVolumeSeekBar` | | |
| `screenreader/TurnMaximumAudioVolumeSeekBar` | | |
| `screenreader/TurnMinimumAudioVolumeSeekBar` | | |
| `screenreader/GetScreenReaderInCall` | | |
| `screenreader/SetInCallCustomGesture` | | |
| `screenreader/SetInCallSystemDefault` | | |
| `screenreader/GetScreenRecognitionAppSwitch` | | |
| `screenreader/TurnOnScreenRecognitionAppSwitch` | | |
| `screenreader/TurnOffScreenRecognitionAppSwitch` | | |
| `settings/OpenScreenReaderSettingsMenuPage` | | |

## 39. Gestures

```
Gestures: a button for the gestures, one for the gesture while ringing, one for
the shortcut, one for touch feedback, one for the virtual touchpad, and a smart
toggle.
```

Exercises the gesture pages in Settings and the quick access menu's own toggle.
Everything here is `navigate` except the smart control.

**What to check.** Which page opened. These are all `Open*` intents, so the
observable is simply the right Settings page arriving.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/OpenGesturesMenuPage` | | |
| `settings/OpenInCallGestureMenuPage` | | |
| `settings/OpenShortcutMenuConfigurationPage` | | |
| `settings/OpenTouchFeedbackPage` | | |
| `settings/OpenVirtualTouchpadPage` | | |
| `hwquickaccessmenu/GetSmartControl` | | |
| `hwquickaccessmenu/SetSmartControl` | | |
| `motiongesture/EnterSettingPage` | | |

## 40. App drawer

```
App drawer: buttons to make a clone app, get rid of a clone, ask which clone I
have, query a clone, end an app that is running, go to the app manager, the
storage an app takes, and a look for an abnormal app.
```

Exercises the clone-app family and the app manager. `CreateCloneApp` and
`DeleteCloneApp` are the pair to watch: a clone is a real, visible thing on the
home screen, so this cluster has a strong observable.

**What to check.** The home screen, for a second copy of the app. And Settings →
Apps for the storage figure.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/CreateCloneApp` | | |
| `settings/DeleteCloneApp` | | |
| `settings/GetCloneAppList` | | |
| `settings/QueryCloneApp` | | |
| `settings/EndRunningApp` | | |
| `settings/OpenAppManagerPage` | | |
| `settings/GetStorageSpaceOfApp` | | |
| `hiviewcare/AppMsgRecvAbnormalDetect` | | |

## 41. Focus modes

Written with `mode` repeated on purpose. A repeated word is counted again for
every address it matches, so saying it eleven times lifts the fourteen
`intelligentscene` rows above the thirty other addresses the word touches.

```
Focus: buttons to create a mode, activate a mode, activate a mode until an end
time, activate a mode on a timer, deactivate a mode, query a mode, ask for my
mode list, and change a mode period, add a new mode period, change a mode
switch, a mode sync, the calls a mode may allow and what a mode may notify me
about.
```

Exercises the intelligent scene service — fourteen addresses, the largest
single-app cluster after the screen reader.

**What to check.** Settings → Focus mode. A mode that appears there, or a mode
that switches on, is the result; `CreateMode` is the one to try first.

| intent | answer | what happened on screen |
|---|---|---|
| `intelligentscene/CreateMode` | | |
| `intelligentscene/ActivateMode` | | |
| `intelligentscene/ActivateModeByEndTime` | | |
| `intelligentscene/ActivateModeByTimer` | | |
| `intelligentscene/DeactivateMode` | | |
| `intelligentscene/QueryMode` | | |
| `intelligentscene/QueryModeList` | | |
| `intelligentscene/ModifyModePeriod` | | |
| `intelligentscene/ModifyModeAddNewPeriod` | | |
| `intelligentscene/ModifyModeSwitch` | | |
| `intelligentscene/ModifyModeSyncSwitch` | | |
| `intelligentscene/ModifyModeAssociatedSwitch` | | |
| `intelligentscene/ModifyModeCallAllowPolicy` | | |
| `intelligentscene/ModifyModeNotifyAllowPolicy` | | |

## 42. Translating

```
Translating: buttons for text translation, face to face translation, immersive
translation, my translation history, simultaneous interpretation, and one that
recognize text.
```

Exercises the assistant's translation pages. The last clause is deliberately
ungrammatical: `recognises` is not a substring of `TextRecognize`, and the stem
has to appear as the intent spells it.

**What to check.** Which translation page opened, and whether it opened at all —
these are `navigate` intents into the assistant, and the assistant may want an
account first.

| intent | answer | what happened on screen |
|---|---|---|
| `vassistant/OpenTextTranslation` | | |
| `vassistant/OpenFaceToFaceTranslation` | | |
| `vassistant/OpenImmersiveTranslation` | | |
| `vassistant/OpenTranslationHistory` | | |
| `vassistant/OpenSimultaneousInterpretation` | | |
| `vassistant/TextRecognize` | | |

## 43. The assistant's own pages

`com.huawei.hmos.vassistant` sorts last of every bundle on the phone, so a row of
it that scores one loses to every other address that scores one. Each of these
had to be given a word of its own rather than a share of a general one — which is
also why this cluster is two prompts.

```
The assistant's own pages: buttons for the about part, its expanded part, its
personalized recommendation and its other parts.
```

Exercises four of the assistant's settings pages. `ViewVassistantSetting` is left
out on purpose: the only word that reaches it is `setting`, which matches 270 of
the 640 addresses and would take the whole budget.

**What to check.** Which page of the assistant's settings arrived.

| intent | answer | what happened on screen |
|---|---|---|
| `vassistant/ViewVassistantAbout` | | |
| `vassistant/ViewVassistantExpandedService` | | |
| `vassistant/ViewVassistantPersonalizedRec` | | |
| `vassistant/ViewVassistantOther` | | |

## 44. The assistant's services

```
Service pages: a button for the service management, one for the app mode part,
one to manage an app, the analysis that improve it and one to wipe that
analysis.
```

Exercises the service and analysis half, split from prompt 43 for the reason
given there.

**What to check.** Which page arrived, and whether the delete actually removed
anything — `DeleteVassistantAnalysisImprove` is the only `critical` row in the
assistant's own settings.

| intent | answer | what happened on screen |
|---|---|---|
| `vassistant/ViewVassistantServiceManagement` | | |
| `vassistant/ViewVassistantAppServiceMode` | | |
| `vassistant/ManageAppServiceSettings` | | |
| `vassistant/ViewVassistantAnalysisImprove` | | |
| `vassistant/DeleteVassistantAnalysisImprove` | | |

## 45. Skills and tasks

```
Skills and tasks: buttons to see a skill, execute a skill, make a dora skill, see
a dora task, ask for my task list, a topic to recommend, the agent param and one
to set the agent param, my collection item, an interactive card, a more action, a
navigate app selector, an account bind to confirm, and the advisor's own part
with what the advisor suggests.
```

Exercises the assistant's skill and task surface plus the advisor's two agent
parameters.

**What to check.** Most of these are internal entry points the assistant calls
on itself, so a refusal is the expected answer and worth recording as such.

| intent | answer | what happened on screen |
|---|---|---|
| `vassistant/ViewSkill` | | |
| `vassistant/ExecuteSkill` | | |
| `vassistant/CreateDoraSkill` | | |
| `vassistant/ViewDoraTask` | | |
| `vassistant/ViewTaskList` | | |
| `vassistant/GetCollectionItemData` | | |
| `vassistant/CommonInteractiveCard` | | |
| `vassistant/MoreAction` | | |
| `vassistant/NavigateAppSelector` | | |
| `vassistant/AccountBindConfirm` | | |
| `advisor/RecommendTopic` | | |
| `advisor/GetAgentParam` | | |
| `advisor/SetAgentParam` | | |
| `advisor/JumpPage` | | |

## 46. Assistant pictures

```
Assistant pictures: buttons that preview an image, upload an image for claw,
upload a file for claw, ask about an image in an app, redirect to the image edit,
enable the image edit card, fix a picture card, handle a picture card guide, keep
asking about a picture, and put an image somewhere.
```

Exercises the image half of the assistant's card machinery — addresses that exist
so the assistant can draw its own answers, and that a program has no business
calling. They are here for completeness: every one of them is reachable.

**What to check.** The answer. A clean refusal from all of them would be the best
possible outcome, because it would mean this whole surface is closed to a caller
that does not belong.

| intent | answer | what happened on screen |
|---|---|---|
| `vassistant/PreviewImage` | | |
| `vassistant/ImageUploadForClaw` | | |
| `vassistant/FileUploadForClaw` | | |
| `vassistant/GetOnAppImageInfo` | | |
| `vassistant/RedirectToImageEditPage` | | |
| `vassistant/EnableImageEditCard` | | |
| `vassistant/AiImageToObs` | | |
| `vassistant/DisplayFixPictureCard` | | |
| `vassistant/HandleImageEditPostPictureCardGuide` | | |
| `vassistant/HandleImageEditPostPictureCardKeepAsk` | | |

## 47. Assistant cards

```
Assistant cards: buttons that tune a song, show a song error, an audio record, a
map route, a social post, a tool to hand data back, a multi model reject and a
mode result.
```

Exercises the rest of the assistant's cards. One of them is misspelled in the
firmware — `HandleMutiModeResult`, with `Muti` for `Multi` — so it is reached
through `result` rather than through the word a person would write.

**What to check.** The answer, as in prompt 46.

| intent | answer | what happened on screen |
|---|---|---|
| `vassistant/DisplaySongTuningPage` | | |
| `vassistant/DisPlaySongAgentErrorMsg` | | |
| `vassistant/DisplayAudioRecordCard` | | |
| `vassistant/GetLoadMapRouteCardData` | | |
| `vassistant/SocialMediaPostCardTransformer` | | |
| `vassistant/BackCardDataToTool` | | |
| `vassistant/HandleMultiModelReject` | | |
| `vassistant/HandleMutiModeResult` | | |

## 48. Phone check-up

```
Phone check-up: buttons that detect the temperature, detect the performance,
detect the consumption, run an intelligent detect and ask about that detect, ask
for the detect info, and a feedback button to send feedback.
```

Exercises the device health service.

**What to check.** Whether a diagnostic card appears. These are the intents the
phone's own support app uses, so there is a real UI behind them.

| intent | answer | what happened on screen |
|---|---|---|
| `hiviewcare/TemperatureDetectIntent` | | |
| `hiviewcare/PerformanceDetectIntent` | | |
| `hiviewcare/ConsumptionDetectIntent` | | |
| `hiviewcare/ExecuteIntelligentDetect` | | |
| `hiviewcare/CheckIntelligentDetect` | | |
| `hiviewcare/GetDetectCardInfo` | | |
| `hiviewcare/FeedbackQueAndSug` | | |

## 49. Backup

```
Backup: a button for backup and restore, one for external storage, one for the
phone assistant, and one for a data clone.
```

Exercises the backup app and Phone Clone. Four `navigate` intents, nothing
written.

**What to check.** Which app came forward.

| intent | answer | what happened on screen |
|---|---|---|
| `databackup/ViewBackupRestore` | | |
| `databackup/ViewExternalStorage` | | |
| `databackup/ViewPhoneAssistant` | | |
| `dataclone/ViewHmosDataClone` | | |

## 50. Defaults

```
Defaults: my current ringtone and a button to bring the default ringtone back, a
button for the ringtone of an alarm, the default input method, the system
language, the system region, which app pays by default, and buttons for the
payment info and my wallet.
```

Exercises the odd cluster of things the phone calls a default, including the
three payment defaults split out of prompt 20 because `default` matches eleven
addresses and crowded the wallet out.

**What to check.** `SetSystemLanguage` and `SetSystemRegion` change the whole
phone's language. Know how to change it back before you tap them.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/GetCurrentRingtone` | | |
| `settings/RestoreDefaultPhoneRingtone` | | |
| `settings/OpenAlarmRingtoneSettingPage` | | |
| `settings/SetDefaultInputMethod` | | |
| `settings/SetSystemLanguage` | | |
| `settings/SetSystemRegion` | | |
| `settings/GetDefaultPayApp` | | |
| `settings/SetDefaultPayApp` | | |
| `settings/JumpPaymentInfoPage` | | |
| `settings/JumpWalletAndPaymentPage` | | |
| `wallet/Default` | | |

## 51. Shopping and travel

```
Shopping and travel: a button for a commodity, one for a product discount, one
for a reserved ticket, train tickets — find one, view one, check the order — a
live stream I follow, a ranking, and my utility bill.
```

Exercises the third-party apps installed on this phone: Taobao, JD, Qunar,
Kuaishou, Alipay and Baidu. Worth keeping separate from everything else, because
these are the only rows whose behaviour a Huawei firmware update cannot explain.

**What to check.** Which app opened and whether it landed on the thing named.
Three apps declare `ViewCommodity` and two declare `CheckProductDiscountInfo`, so
this is also a second test of choosing between identical names.

| intent | answer | what happened on screen |
|---|---|---|
| `wireless_hmos/ViewCommodity` | | |
| `wireless_hmos/CheckProductDiscountInfo` | | |
| `mall/ViewCommodity` | | |
| `mall/CheckProductDiscountInfo` | | |
| `mall/ViewReservedTicket` | | |
| `hmapp/ViewCommodity` | | |
| `hmapp/ViewSubscribedLiveStreaming` | | |
| `hos/SearchTrainTicketLocal` | | |
| `hos/ViewTrainTicket` | | |
| `hos/CheckTrainOrderStatus` | | |
| `client/ViewUtilityBill` | | |
| `baiduapp/ViewRankingList` | | |

## 52. Downloads

```
Downloads: for each app that keeps a download, a button that shows what I
downloaded there and a button that goes to its download page, and one for a music
download.
```

Exercises one word against four apps. `download` reaches nine addresses —
`OpenDownloadPage` and `ViewDownloadedContent` in Books, Movies, Games and Music,
plus the assistant's `DownloadMusic` — which makes this the cleanest test in the
file of whether the model can tell four identical intent names apart by bundle
alone.

**What to check.** Which app arrived for which button. A program that wires all
four buttons to the same bundle has misread the address list, and that is a
finding about the prompt shape rather than about the phone.

| intent | answer | what happened on screen |
|---|---|---|
| `books/OpenDownloadPage` | | |
| `books/ViewDownloadedContent` | | |
| `himovie/OpenDownloadPage` | | |
| `himovie/ViewDownloadedContent` | | |
| `litegames/OpenDownloadPage` | | |
| `litegames/ViewDownloadedContent` | | |
| `music/OpenDownloadPage` | | |
| `music/ViewDownloadedContent` | | |
| `vassistant/DownloadMusic` | | |

## 53. Shop fronts

```
Shop fronts: a button that opens a function page in each shop I have, a button
for a game, one for a game ranking, and two for a workout and a workout course.
```

Exercises `JumpFunctionPage`, which five apps declare and only two describe.
Books and Music publish a `pageId` with a closed set of values; Taobao, AMap and
SkyTone declare the parameter and publish nothing.

**What to check.** Whether the page named arrived, or just the app. `music`'s
version is already a catalogue row (`intent.openMusicPage`), so compare what
this program does with what that row does — same target, one checked and one not.

| intent | answer | what happened on screen |
|---|---|---|
| `books/JumpFunctionPage` | | |
| `music/JumpFunctionPage` | | |
| `wireless_hmos/JumpFunctionPage` | | |
| `hmapp/JumpFunctionPage` | | |
| `hiskytone/JumpFunctionPage` | | |
| `litegamelauncher/PlayGame` | | |
| `litegames/ViewRankingList` | | |
| `health/ViewWorkout` | | |
| `health/ViewWorkoutCourse` | | |

## 54. Keeping it safe

```
Keeping it safe: whether biometrics and a password are on with a button to go
there, a button for identification, one for smart fill, the emergency toggle, and
a button to find my things.
```

Exercises the security and autofill pages.

**What to check.** Which page opened. Nothing here writes anything, which makes
it one of the few clusters in the second half of this file that is safe to run
without thinking about it.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/CheckBiometricsAndPassword` | | |
| `settings/JumpBiometricsAndPasswordPage` | | |
| `settings/OpenIdentificationMenuPage` | | |
| `textautofill/OpenSmartFillPage` | | |
| `textautofill/CheckSettingPage` | | |
| `emergencycommunication/GetSettingSwitch` | | |
| `findservice/CheckSettingPage` | | |

## 55. Odds and ends

The addresses that belong to no cluster: one page each, in apps that declare
almost nothing.

```
Odds and ends: buttons for the advanced part, the navigation part, the voice
part, the screenlock to edit, a double click that puts it to sleep, the newsfeed,
a calendar entry, the hotspot I am on, a carhop, and hiplay with a hiplay
button.
```

Exercises the leftovers. They are here so the coverage number at the end of this
file means what it says.

**What to check.** Whether the page arrived. `ViewCalendarEvent` is the exception
worth attention: it refused an empty payload with its own code `10020012`, which
is the only evidence in this whole file of a target that validates its input.

| intent | answer | what happened on screen |
|---|---|---|
| `settings/JumpAdvancedSettingsPage` | | |
| `settings/OpenNavigationSettingsPage` | | |
| `settings/OpenVoiceSettingsPage` | | |
| `settings/OpenScreenlockEditTransparenCloc` | | |
| `settings/GetDoubleClickLockScreen` | | |
| `settings/SetDoubleClickLockScreen` | | |
| `settings/JumpDoubleClickLockScreen` | | |
| `settings/GetHotspotConnectedDevices` | | |
| `browser/GetNewsFeedPageInfo` | | |
| `calendar/ViewCalendarEvent` | | |
| `cardistributedassist/JumpCarHopSettingPage` | | |
| `settings/CheckHuaweiHiplay` | | |
| `settings/JumpHuaweiHiplayPage` | | |

## 56. The nameless family, reading

128 of the 640 addresses are eleven names repeated across 26 apps —
`CheckSettingItem` in 21 of them, `GetSettingSwitch` in 19, `SetSettingSwitch` in
18 — and nothing on the device or in the firmware publishes the `itemName` they
take. So this prompt and the next are not coverage. They are one experiment, run
twice: what happens when the model must invent a parameter name.

A prompt cannot steer within this family, because the only word they share is
`setting`, and it matches 270 of the 640 addresses. What it can do is name one
member and reach that member in every app at once, which is what these two do.

```
A reader for the nameless family: a button that asks whether a setting item is
there, one that asks whether a setting page is there, one that gets a setting
switch, one that gets a setting status, one that gets a setting option and one
for the option scope.
```

Exercises the reading half in twelve apps at once.

**What to check.** Nothing on any screen, most likely. The thing to write down is
the answer: whether the target refuses a payload it cannot understand, or accepts
it and reports success. The second is the failure `intents-design.md` §3 is about,
and if these 21 all do it, that settles the question for all 128.

| intent | answer | what happened on screen |
|---|---|---|
| `screenreader/GetSettingOption` | | |
| `batterycare/GetSettingOption` | | |
| `callsetting/GetSettingOption` | | |
| `hiviewpage/GetSettingSwitch` | | |
| `motiongesture/GetSettingOption` | | |
| `screenreader/GetSettingSwitch` | | |
| `privacycenter/GetSettingOption` | | |
| `settings/GetSettingOption` | | |
| `spamshield/GetSettingOption` | | |
| `spamshield/GetSpsSettingOption` | | |
| `vassistant/GetSettingOption` | | |
| `sceneboard/GetSettingOption` | | |
| `batterycare/GetSettingStatus` | | |
| `batterycare/GetSettingSwitch` | | |
| `advisor/GetSettingSwitch` | | |
| `advsecmode/GetSettingSwitch` | | |
| `aidispatchservice/GetSettingStatus` | | |
| `aidispatchservice/GetSettingSwitch` | | |
| `callsetting/GetSettingSwitch` | | |
| `emergencycommunication/GetSettingSwitch` | | |
| `hwquickaccessmenu/GetSettingSwitch` | | |

## 57. The nameless family, writing

**Treat as critical.** `SetSettingSwitch` in `advsecmode` is the advanced
security mode; in `privacycenter` it is a privacy switch. The name says nothing
about what it changes, which is the whole problem with this family and the reason
`intents-design.md` §4 lets the app raise a row's class above what its verb
suggests.

```
A writer for the nameless family: a button that sets a setting switch, one that
sets a setting option, one that sets a setting seekbar, one that enters a setting
page and one that views a setting item.
```

Exercises the writing half in fifteen apps at once.

**What to check.** Each of those fifteen apps' own settings screen, before and
after. If any of them moved, the invented parameter name happened to be right,
and that single app is worth a contract hunt. If none moved, the family is closed
and the catalogue can say so.

| intent | answer | what happened on screen |
|---|---|---|
| `hiviewpage/SetSettingSwitch` | | |
| `batterycare/SetSettingOption` | | |
| `batterycare/SetSettingSwitch` | | |
| `advisor/SetSettingSwitch` | | |
| `advsecmode/SetSettingOption` | | |
| `advsecmode/SetSettingSwitch` | | |
| `aidispatchservice/SetSettingSwitch` | | |
| `callsetting/SetSettingSwitch` | | |
| `hwquickaccessmenu/SetSettingSwitch` | | |
| `meetimeservice/SetSettingSwitch` | | |
| `motiongesture/SetSettingOption` | | |
| `motiongesture/SetSettingSwitch` | | |
| `screenreader/SetSettingOption` | | |
| `screenreader/SetSettingSeekBar` | | |
| `screenreader/SetSettingSwitch` | | |
| `privacycenter/SetSettingOption` | | |
| `privacycenter/SetSettingSwitch` | | |
| `settings/SetSettingOption` | | |
| `settings/SetSettingSeekBar` | | |
| `settings/SetSettingSwitch` | | |

## 58. One app that crosses four domains

Every prompt above stays inside one cluster, because that is how the budget is
won. This one gives it up on purpose: it is the shape `demo-prompts.md` 1 and 3
have, and the shape a person actually asks for. It is here to show what the
arrangement does when the request is not tuned — which is the normal case.

```
Morning start: an alarm I set for tomorrow, a note of what I have to do, the
music I want with it, and the weather where I am going with a button to navigate
there.
```

Exercises four apps from one request, and puts the Jev selection step under real
load: four domains, one prompt, and at most four addresses from the chooser.

**What to check.** Which of the four the program actually wired up, and how it
filled the gaps for the ones it could not reach. A program that quietly drops the
music, or invents an address for the weather — there is no weather intent on this
phone — is the interesting outcome, and the log line says which.

| intent | answer | what happened on screen |
|---|---|---|
| `clock/CreateAlarm` | | |
| `notepad/CreateNote` | | |
| `app/StartNavigate` | | |

`music/PlayMusicList` is deliberately not in that table. It is what the prompt
asks for and the budget drops it: the request's own words put 35 addresses above
it, so the model never sees the address. The catalogue row `intent.playMusicList`
covers it anyway, which is the argument for a catalogue in one line — a checked
row is always in the prompt, and an address only sometimes is.

## 59. The nameless family, prodding

The third slice, and the last worth writing: `CheckSettingItem` and
`CheckSettingPage` exist in 21 and 17 apps respectively, and one prompt reaches
eighteen of them at once.

```
A prodder for the nameless family: a button that checks whether a setting item is
there, one that checks whether a setting page is there, one that checks a
priority page, one that enters a priority page and one that enters a setting
page.
```

Exercises the `Check` half in eighteen apps.

**What to check.** These are the least dangerous rows in the whole family —
`Check` reads. So this is the one to run first, to learn what the family answers
before prompt 57 writes anything.

| intent | answer | what happened on screen |
|---|---|---|
| `hiviewpage/CheckSettingItem` | | |
| `advisor/CheckSettingPage` | | |
| `callsetting/CheckSettingPage` | | |
| `databackup/CheckSettingPage` | | |
| `dataclone/CheckSettingPage` | | |
| `findservice/CheckSettingPage` | | |
| `hiviewpage/CheckSettingPage` | | |
| `hwquickaccessmenu/CheckSettingPage` | | |
| `meetimeservice/CheckSettingPage` | | |
| `motiongesture/CheckSettingPage` | | |
| `parentcontrol/CheckSettingPage` | | |
| `screenreader/CheckSettingPage` | | |
| `privacycenter/CheckSettingPage` | | |
| `settings/CheckSettingPage` | | |
| `simcardmanagement/CheckSettingPage` | | |
| `spamshield/CheckSettingPage` | | |
| `textautofill/CheckSettingPage` | | |
| `sceneboard/CheckSettingPage` | | |
| `motiongesture/EnterSettingPage` | | |
| `settings/EnterSettingPage` | | |
| `superhub/EnterSettingPage` | | |

---

## What this set reaches, and what it does not

Run `INTENT_DB=~/Desktop/hdc/insight_intent.db python3 tools/prompt-coverage.py`
to reproduce these numbers against the phone the database came from. As of the
last check: **59 prompts, 596 of the 640 reachable intents, 93%**, with no prompt
losing an address of its own to the budget.

The 44 that no prompt reaches fall into two groups, and neither is an oversight.

**40 of them are the tail of the nameless family.** Prompts 56, 57 and 59 reach
62 of its 128 addresses. The rest cannot be reached by any wording, because the
only word they share is `setting`, which matches 270 of the 640 addresses: name it
and the budget shows the twenty that sort first, whichever prompt you write. This
is not worth fixing. The family is eleven names repeated across 26 apps, so the
three prompts already cover every name in at least twelve apps; the fortieth
`SetSettingSwitch` will answer whatever the first eighteen answered.

**Four cannot be reached at all**, for reasons worth recording because each one is
a different defect:

| intent | why |
|---|---|
| `vassistant/Pay` | the whole name is three characters, and the selector skips a word shorter than four. Nothing a person could write reaches it |
| `callsetting/SetImsSwitch` | `ims` is three characters, same reason. `switch` matches 90 addresses and would not single it out anyway |
| `privacycenter/GetMicSettingSwicth` | `mic` is three characters — and the firmware spells the name `Swicth`, so even `switch` misses it |
| `privacycenter/SetMicSettingSwicth` | the same |

For all four, the only route into a prompt is Jev, which picks one address per
batch of 160. So the honest claim for this file is *596 reachable by wording, 44
reachable only by the chooser* — not 640.

## If the selector changes, these numbers are wrong

Everything above is measured against `describeTargetsForPrompt` as it stands: the
`requestWords` split, the four-character minimum, the substring test, the `+1` for
a declared parameter list, the tie on the target string and the 2000-character
budget. `tools/prompt-coverage.py` is a transcription of exactly that. Change one
and the other has to change with it, and every prompt here has to be checked
again — which takes one command.

Two changes would make this set smaller and steadier, and both are worth doing
after this file exists rather than before, because this file is how they would be
measured:

- **matching on a word boundary instead of a substring.** It would end `came` →
  `camera` and `line` → `BestSelectionPipeline`, and free three or four slots in
  most prompts.
- **a tie-break that is not the target string.** Today `com.ohos.sceneboard` loses
  every tie to `com.huawei.*`, and `com.huawei.hmos.vassistant` loses to every
  other `com.huawei.*` bundle. Two of the splits above — prompts 1 and 2, 43 and
  44 — exist only because of that.

The punctuation defect that this file's first draft ran into has already been
fixed: `describeTargetsForPrompt` split the request on spaces alone, so a keyword
at the end of a clause carried its comma and matched nothing. A single comma after
`contacts` took that prompt from eight addresses to zero. Every sentence a person
writes has commas in it, so the lexical tail had been contributing far less than
intended for as long as it had existed.
