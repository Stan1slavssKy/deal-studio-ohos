# Prompts for the composed blocks

What the Jev template path should build from these, without a model rewrite (`action=template`). The blocks are
general (record_log is the source, number_strip / breakdown_table / series_chart / settle_up read what it
publishes); none of them says "expenses", so the same blocks answer the other prompts too. Record what the phone
actually did in the last column.

| prompt | layout | blocks | what to check | phone did |
|---|---|---|---|---|
| Shanghai 11-hour layover stop manager (gold set, `docs/prompts/template-select-gold.json`, full prompt) | itinerary_day | itinerary (navigation and calendar slots on), progress_line | header line, windows from 09:00, N of 9, Navigate opens Petal Maps, Add to calendar then Open calendar shows the event, Wipe removes only this app's events | itinerary_day@1.00, itinerary@0.97, progress_line@0.96 (list_summary@0.80 dropped: one progress slot); template, no model rewrite; reached 1 of 9, event added and wiped, Petal Maps opened its route screen (from the phone's position: it ignores srcLocation) |
| Shared costs between four friends, Anna, Ben, Carol and Dan: any of them sometimes pays for everyone. Let me pick who paid, enter the amount in dollars and cents and add it with a short note, and keep the list of all payments. Everything is split equally. Show the total spent, the equal share, how much each has paid and the balance of each, who should pay whom to settle, a bar chart of what each has paid, a button to remove the last payment and one to start over. | log_report | record_log, number_strip, breakdown_table, series_chart, settle_up | add 120 for Anna and 60 for Carol: total 180, share 45, Ben pays Anna 45, Dan pays Anna 30, Dan pays Carol 15 | |
| Roommates split groceries and rent, show who owes whom | log_report | record_log, breakdown_table, settle_up | same numbers logic, no chart | |
| Log my workout minutes per exercise and show a bar chart | log_report or stack | record_log, series_chart | totals per exercise | |
| Points per player in a board game, show the table | log_report | record_log, breakdown_table | no money: set the currency caption empty | |
| Hours worked per team member this week, who did the most | log_report | record_log, breakdown_table, series_chart | | |
| Budget tracker with categories and spending charts (gold set) | log_report | record_log, series_chart | | |
| A simple scoreboard for a card game with two players (gold set) | any | | may stay on the model: it wants + and - counters, not records | |

`tools/template-select-eval.py` on `docs/prompts/template-select-gold.json` before and after these blocks gives the
share that ends as template, complete and scratch; Jev's round trip is the `VERA-SECTIONS ms=` line in hilog.
