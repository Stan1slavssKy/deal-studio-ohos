# The demo prompts

Typed into the Generate screen as they stand. Each is a plain description of an
app, with no mention of intents, modules or APIs — what the program reaches for
is the model's decision, made from the catalogue the prompt carries.

## 1. Layover planner, Istanbul

```
Istanbul layover: I land at Istanbul Airport at 08:00 with 12 hours before my
next flight. Plan the day hour by hour around the sights worth seeing, each stop
with its name, how long to spend there and its coordinates, a button that starts
navigation to it from the last stop I reached, a button that puts the stop in my
phone's calendar with a reminder, and the latest time I must leave for the
airport. Keep a note of which stops I actually reached, and give me a button that
wipes every calendar event this app added and one that opens the phone's
calendar.
```

Exercises `std/intent` → `navigateTo`, the row that carries an object parameter
through a flat record.

**Why the city is in the prompt rather than in a text field.** A VERA-L program
has no network: `ui.Image` can name an https URL and nothing else can reach out.
So the itinerary — which sights, in what order, at what coordinates — has to be
in the program, and it gets there when the model writes it. Changing the city
means generating again, which is the tool working as intended: the prompt is the
input.

**What to check, and it is not the result code.** `ExecuteResult.code` is chosen
by the target's developer; Petal Maps answers 0 to `ViewSearchPageLocal` while
ignoring the query. So: tap a stop's navigation button and look at the screen.
A route to the right place, or it did not work. Then check the coordinates
landed in Istanbul rather than somewhere the model imagined — a wrong latitude
is a plausible failure here, and the only one that a green route on screen will
not reveal.

## 2. Pill tracker

```
Pill tracker: let me add a medicine with a name, the hour and minute to take it
and whether it repeats every day; each one goes into the phone's calendar with a
reminder, and the list below shows what is scheduled and what the calendar
answered.
```

There is no `std/calendar` any more: a program reaches the calendar only through
`sdk.call`, and only for what `find_sdk_function` or `find_intent_function`
returns. Whether the phone's calendar is reachable that way is the thing this
prompt checks.

**What to check.** Open the phone's Calendar app afterwards. The event is either
there at the right time, repeating or not as asked, or it is not. The program's
own log only repeats what the host told it.

**The permission is a real branch.** `WRITE_CALENDAR` is user_grant: the dialog
appears once at startup and can be refused, and every call then answers with an
error. That is a legitimate outcome and the program is told to show it, so a
screen full of errors after a refusal is the app working, not failing.

## 3. Layover planner, Shanghai

The same app as the first prompt in a different city, kept because one city is
not evidence. The itinerary is written by the model, so a plan that comes out
right for Istanbul says nothing about whether the coordinates were recalled or
invented — a second city that also lands on the map is the check.

```
Shanghai layover: I land at Pudong International Airport at 09:00 with 11 hours
before my next flight. Plan the day hour by hour around the sights worth seeing,
each stop with its name, how long to spend there and its coordinates, a button
that starts navigation to it from the last stop I reached, a button that puts the
stop in my phone's calendar with a reminder, and the latest time I must leave for
the airport. Keep a note of which stops I actually reached, and give me a button
that wipes every calendar event this app added and one that opens the phone's
calendar.
```

Shanghai layover: I land at Pudong International Airport at 09:00 with 11 hours before my next flight. Plan the day hour by hour around the sights worth seeing, each stop with its name, how long to spend there and its coordinates, a button that starts navigation to it from the last stop I reached, a button that puts the stop in my phone's calendar with a reminder, and the latest time I must leave for the airport. Keep a note of which stops I actually reached, and give me a button that wipes every calendar event this app added and one that opens the phone's calendar.

Exercises everything the device can reach at once: `navigateTo` for each leg,
a calendar write for each stop and for clearing the run before this one (found
through `find_sdk_function`), and `openCalendar`, which launches the app rather than sending it an
intent.

What the model actually wrote for it is kept verbatim in
[`examples/shanghai-layover.vera`](examples/shanghai-layover.vera) — useful for
seeing which components it reaches for without being told, and worth re-recording
whenever the catalogue or the prompt changes.

**What to check.** The stops should sit within Shanghai — roughly 31.2° north,
121.4–121.5° east; Pudong airport itself is out at 121.81. A tap on a stop's
navigation button draws a route on Petal Maps or it does not; the result code
will not tell you, because the target's developer chooses it. Then open the
calendar and count: one event per stop that was added, at the hour the plan
names.

**The first leg starts from the phone, not the airport.** Petal Maps accepts
`srcLocation`, answers 0 and routes from wherever the phone actually is; this
was pinned down twice, the second time without a confound. The program is still
right to say where each leg begins, and every leg after the first is correct as
soon as you are standing at the stop it starts from.

## 3a. Shared costs between four friends

```
Shared costs between four friends, Anna, Ben, Carol and Dan: any of them sometimes
pays for everyone. Let me pick who paid, enter the amount in dollars and cents and
add it with a short note, and keep the list of all payments. Everything is split
equally among the four. Show the total spent, each person's equal share, how much
each one has paid so far, and each person's balance (positive means the others owe
them, negative means they owe). Show who should pay whom to settle everything with
the fewest transfers, and a bar chart of what each friend has paid. Give me a
button to remove the last payment and one to start over.
```

The calculation prompt: no phone API, but real arithmetic on user input, a list that
grows, and a chart. Added after the Shanghai prompt because it sits at the other end
of the range — Shanghai is all device integration, this is all logic. It is also the
kind of request the Jev template path now has to hand to the model: a list, a form
and a bar chart are fragments, the money maths is not.

**What to check.** Enter Anna 120.00, Ben 60.00, Dan 20.00 and nothing for Carol:
the total is 200.00 and each share 50.00. Balances are Anna +70.00, Ben +10.00,
Carol -50.00, Dan -30.00, and the settlement has three transfers: Carol pays Anna
50.00, Dan pays Anna 20.00, Dan pays Ben 10.00. The bars read 120, 60, 0 and 20.
Remove the last payment and every figure redraws without it.

**Where it can go wrong.** Amounts are money, so they should be kept in cents and
shown through a helper, never as floating point: 0.10 + 0.20 must come out as 0.30.
A total that does not divide by four leaves a cent over; the program should say who
carries it rather than make the balances not sum to zero. The sum of all four
balances is always zero, which is a cheap check on any run. A bar chart with all
payments at zero must not divide by zero.

## 4. Blink melody, flashlight in time

```
A button that plays an 8-second melody in C major at 120 BPM, four notes per bar,
built from sine tones computed sample by sample with math.sin at 8000 samples per
second, sent as comma-separated 16-bit samples to the platform audio renderer
write call with sampleRate 8000. On every beat the flashlight turns on, and it
turns off 80 milliseconds later, in time with the melody. When the melody ends,
the flashlight is off and the app shows how many beats it blinked.
```

Exercises the audio renderer and the torch together. The first version was
generated at 8 seconds and exceeded the interpreter's step budget (5 000 000 steps
for one action), so it was asked for 5 seconds with "What to change?". The first
version also omitted `sampleRate`, so the melody played about six times too fast
until it was asked for explicitly.

**What to check.** The melody lasts about 5 seconds at 120 BPM, which is ten beats.
The flashlight flashes on each beat and goes off 80 ms later. The flashes are driven
by the program's tick, not by the audio clock, so they can drift against the sound;
check by ear and by eye. It is one button press, not a loop.

## 5. Chat with widgets (a separate screen)

Unlike the four above this is not typed into the Generate screen. It is the
**Chat** side of the switch on the home screen (`pages/ChatPage`): an ordinary assistant
conversation in which a reply can carry a live mini-application, generated while
the person waits and drawn inside the conversation, the way a chat answer can
embed an interactive component instead of describing one.

Messages to type, in one conversation:

```
We are four people and the bill is 187.40, we want to leave 12% tip. Who pays what?
```
```
What is a good way to learn 20 Spanish words a week?
```
```
I need to boil an egg, soft, the way I like it.
```
```
My room is pitch dark and I cannot find my keys. Give me a button to turn the flashlight on and one to turn it off.
```

**How it works.** Each turn is a streamed chat completion (`vera/VeraChat.ets`
`chatReply`: the words appear as they arrive) whose system prompt lets the assistant end a reply with
`<<app: ...>>`, a one-line English description of a widget, anywhere in the
reply: before the text, between two parts of it, or after it. The text streams in
and the widget starts building the moment its line is closed, while the rest of
the reply is still arriving. The description then goes through the same pipeline as the Generate screen
(skill prompt plus `rawfile/vera-widget.txt`, a widget-mode section that asks
for one purpose, no title block, results first and no scrolling, and shows money
through a `money()` helper rather than as raw cents; `find_sdk_function` /
`find_intent_function`, compiler with up to three attempts) and the resulting program is rendered by `VeraPreview` in a
fixed-height (420 vp) card under the message. Widget builds are queued, one at a time.

**What to check, and what a phone run showed.**
- The first message gives a text answer and a split-the-bill widget with 187.40,
  four people and 12% already in it (total 209.88, 52.47 each, matching the
  text). Tapping "+" on people moved 4 to 5 and the figures redrew. One build
  failed to compile on the first attempt and passed on the second, so expect
  about a minute.
- The second is expected to get text, and a widget is acceptable: the model
  usually adds a weekly tracker (Learned 0/20, four sets to tick off). The system
  prompt says "never for something a sentence answers" and it does not reliably
  hold; it was left as it is, as good enough for a demo.
- The third gets a soft-boiled egg timer with presets and a countdown that really
  ticks (337 s, then 321 s sixteen seconds later).
- The fourth uses a system intent. The assistant answers briefly and offers a
  widget with Turn On / Turn Off buttons and a "Last platform answer" panel; the
  buttons reach the phone's torch through `sdk.call` (found with
  `find_intent_function`, `sceneboard/OpenFlashlight` and `CloseFlashlight`).
  Confirmed on a phone by watching the torch light and go out, which is the only
  check that counts: the panel says `ok` either way. The widget also shows
  counters ("Times switched on 10") that the model seeded rather than measured.
  Without the capability sentence in the chat system prompt the assistant
  refused ("I can't control your phone's flashlight"), and an alarm prompt ("flight
  at 08:40, help me not oversleep") built a planner that told the person to set
  the alarms by hand; the sentence that lets widgets act on the phone is what
  changed that.
- A fifth, with web search and a photo: "Show me the Pushkin Museum of Fine Arts in
  Moscow with a photo of it and its opening hours." Needs an Exa key
  (`--ps exaKey ...`) and a network Exa does not block (it blocks Russian
  addresses). The assistant searches (once for the hours, once for a photo), cites
  the source in its text, and the widget shows the photo through `ui.Image` with
  the address, hours and a Directions button. The image address must be one the
  search returned; the one in the run above was checked against Exa's own
  results. Without the key there is no search and no photo.
- **Saved chats and stats.** Chat on the home screen opens a new chat; the clock
  icon in its header, or the clock at the top right of the home screen in Chat
  mode, opens the list of saved chats (newest first, with message count,
  widgets and estimated cost; swipe a row to delete it) and a New chat button. A chat is saved as it goes, including each widget's
  program and its own state (`{filesDir}/vera/chats`, and `chat-<id>/` for widget
  state), so reopening it, even after the app was stopped, shows the same
  conversation and the same widgets. A widget that was still being built when
  the chat was closed comes back marked as not finished. The **Stats** switch on
  the chat screen shows the numbers the Generate screen's metrics pane shows,
  for the whole chat at the top and under each reply: time, estimated cost, LLM
  wall time against on-device compile time, input / cached / fresh / output
  tokens, web searches, and for each widget build attempt its wait, think,
  write, compile and speed. Cost uses DeepSeek's published rates and is an
  estimate.
- A failed build shows the error under the reply instead of leaving a spinner;
  this was seen when the phone lost Wi-Fi mid-build. The conversation continues.
- The conversation is not saved, and neither is a widget's state: leaving the
  screen discards both.
- The widget scrolls inside its 520 vp card, which sits inside the message list;
  no fight between the two was seen on ordinary use, but drags were not stressed.
  Generated layouts are not checked for fit, so a label can wrap badly ("Thursd /
  ay" in a half-width tile).

Run on a phone (debug-signed as a system app, DeepSeek key stored): Chat on the
home screen opens the screen.

## 6. Chat starters and the home screen

The home screen has a Chat / App switch, a box at the bottom and, above the
box, the starters below as cards in a row that scrolls sideways
(`HOME_STARTERS` in `entry/src/main/ets/components/ChatStarters.ets`): first
the three chat starters, then four app demos. An EN / 中文 switch next to "Try
one of these" changes the cards and the prompt a card sends; it opens on EN. A card sends its English
prompt in the mode that is on: to a new chat in Chat, to a new app in App. What
is typed into the box goes the same way. "My apps ›" at the right of the cards'
header hides the box and opens a horizontal shelf of the saved apps with large
icons; the cross or Back closes it. The button at the top right opens the
saved chats in Chat mode and the My apps list in App mode.

A new, empty chat shows a list of ready-made first messages ("prompt
starters"). A tap sends one as if it had been typed; the list goes away once
the chat has a message, and the chat is saved like any other. An EN / 中文
switch above the list picks the language; it is kept while the app runs. The
prompts live in `STARTERS_ZH` and `STARTERS_EN` in
`entry/src/main/ets/components/ChatStarters.ets`.

| starter | 中文 | EN |
|---|---|---|
| 旅行计划 / Trip plan | 我们一家三口要去西湖玩一天，帮忙计划行程。 | We are a family of three going to West Lake for a day. Help us plan the itinerary. |
| 宝宝护理 / Baby fever | 我宝宝发烧了，37.5度。帮我创建宝宝发热护理卡片与服务。 | My baby has a fever of 37.5°C. Create a baby fever care card and services for me. |
| 吃药提醒 / Pills | 帮我创建一张吃药卡，提醒我每天吃药。 | Create a medicine card that reminds me to take my pills every day. |

For 旅行计划 the presenter pastes a travel-guide link as the next message when
the model asks. Chat cannot open the link itself: the plan comes from the
model's own knowledge and web search, with the link as context.

The four app demos on the home screen, after the three chat starters. Each card
sends the English prompt; the Chinese is the brief it was written from.

| card | brief | EN prompt |
|---|---|---|
| Tank battle | 帮我做一个小时候红白机风格的坦克大战，像素画面，能移动、开炮、打掉砖墙，消灭敌人并保护基地。 | Make a retro tank battle game in the pixel style of the 8-bit game consoles I played as a child: my tank moves and fires, shells knock out brick walls, and I destroy the enemy tanks while protecting my base. |
| Exam prep | 学生从社区发现一个同学做好的备考工具，通过一句话换成自己的学校和课程；进入个人 miniapp 后拍下自己的复习材料，才建立与个人材料对应的题库。 | Make an exam prep tool for my own school and course: I photograph my revision materials and it builds a question bank from them for me to practise on. |
| Grades & GPA | 帮我做个成绩和绩点计算器，叫"好绩将至"……桌面放一张 2×2 卡片，只写"好绩将至"和"课程成绩 · 学期绩点"，不要显示我的成绩。 | Make a grade and GPA calculator called "好绩将至" (Good Grades Ahead)… (full text in `HOME_STARTERS`) |
| Timetable | 这是我这学期的选课明细，帮我做一个课表，可以按天、按周查看……以后可以拍照重新导入，也可以从日历导入课程。 | Make a class timetable from my course list for this term that I can view by day and by week… (full text in `HOME_STARTERS`) |

Tank battle has a second step, typed as a refinement once the game is built:

```
Replace my tank with my corgi "Tuantuan" and the enemy tanks with my friend's
black-and-white border collie "Doudou". I will upload their photos: keep each
one's coat colours and shape and make them cute pixel art. Bullets become small
bones, the base becomes a dog house, and the fire button says "Throw bone".
Everything else plays the same.
```

The exam-prep brief starts in the community: a classmate's tool is remixed with
one sentence naming the student's own school and course. The card covers only
the second half, the personal app built on the student's own photographed
material. The GPA and timetable briefs refer to an attached conversion table and
course list; the prompts ask for them to be entered or imported instead.

## 7. Starting a new app

On the App side of the home screen, the box (or a card) opens the Generate
screen at once: no name or picture is asked for, and no project exists yet; the
"+" on the Generate screen starts another. An empty Generate screen lists
ready-made prompts by group (`APP_STARTERS` in
`entry/src/main/ets/components/ChatStarters.ets`, English only, as the generator
wants): sections 1, 2, 3a and 3 above, the wind-down request ("I'm in bed, don't
know what to do, create an app for me"), the three chat starters of section 6 in
English, then short one-sentence briefs (water, pantry, feeding, homework,
chores, reading, service, fuel, filters, 2048, minesweeper); a tap fills the box
and starts generating.

The project is made at the first **Save**, which asks for its name and offers
one: the title of the program's own `ui.Header`, else the first words of the
request, else "New app" (`vera/AppName.ets`). The window shows the picture beside the name; a
tap on the picture opens the ten to choose from (`components/IconPicker.ets`), the
phone being the one to start with. On the project page the picture and the name
are the controls too: a tap on either changes it, and a pencil marks them. Saves
after that are new versions with no question.

**Back** with work that was not saved asks first. With a result that no version
holds it asks "Save this app?" (Save, Discard, Keep editing), for a new app and
for a refine of an existing one. With only a request typed into either box, or a
run under way, there is nothing to save, so it asks "Leave without generating?"
(Discard, Keep editing). Back from an empty screen, or with everything saved,
leaves at once, and a new app that was never saved leaves nothing behind in the
list.

## What none of the prompts say

None of them mentions `intent`, `calendar`, a bundle name or a parameter. The model
is given the catalogue in its prompt and picks from it. That is the whole point
of the arrangement: a generated program cannot name a platform parameter,
because it never sees one.
