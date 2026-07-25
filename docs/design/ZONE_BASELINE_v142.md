# Zone combat baseline — post-3.75x rebase (v142)

Ungated baseline for every transition, measured with:
`z3_funnel.tscn -- --zone=N`

Read: config 9 (Common N) MUST farm all four with no deaths (owner idle rule).
Where it does not, the ZONE is mis-calibrated — gate only after that is fixed.

## Zone 2
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   16*            8*             6D             4             
5 Legend N-1    T1 cores   17*            9*             7*             4             
6 Legend N-1    T2 cores   19*            10*            8*             5*            
7 Legend N-1    T3 cores   23*            12*            8*             5*            
8 Unique N-1    no cores   122*           73*            12*            41*           
9 Common N      no cores   17*            10*            7*             5*            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 3
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   8*             5*             2              2             
5 Legend N-1    T1 cores   9*             5*             4              2             
6 Legend N-1    T2 cores   10*            6*             5*             2             
7 Legend N-1    T3 cores   13*            7*             6*             2             
8 Unique N-1    no cores   22*            14*            9*             6*            
9 Common N      no cores   17*            11*            9*             5*            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 4
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   2D             2D             2              3D            
5 Legend N-1    T1 cores   4              3              2              4             
6 Legend N-1    T2 cores   5*             2              3              1D            
7 Legend N-1    T3 cores   6*             4              3              5*            
8 Unique N-1    no cores   12*            9*             6*             10*           
9 Common N      no cores   5*             3              2              4             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 5
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   1D             1D             2              0D            
5 Legend N-1    T1 cores   4D             3D             3              1D            
6 Legend N-1    T2 cores   7*             0D             3              2D            
7 Legend N-1    T3 cores   8*             6D             4              5D            
8 Unique N-1    no cores   19*            16*            9*             17*           
9 Common N      no cores   9*             6*             4              8D            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 6
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   5*             3D             2              4D            
5 Legend N-1    T1 cores   5*             6D             2              5D            
6 Legend N-1    T2 cores   8*             7*             3              7*            
7 Legend N-1    T3 cores   7*             7*             3              7*            
8 Unique N-1    no cores   17*            15*            7*             16*           
9 Common N      no cores   6*             5*             2              5*            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 7
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   0D             0D             0D             1             
5 Legend N-1    T1 cores   0D             1D             0D             1             
6 Legend N-1    T2 cores   1D             3D             1D             2             
7 Legend N-1    T3 cores   1D             4              2D             2             
8 Unique N-1    no cores   12*            6*             8*             4             
9 Common N      no cores   6D             3              4              2             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 8
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   3D             7*             2D             3             
5 Legend N-1    T1 cores   3D             9*             7D             4             
6 Legend N-1    T2 cores   11*            12*            10*            5*            
7 Legend N-1    T3 cores   12*            11*            9D             5*            
8 Unique N-1    no cores   27*            28*            24*            12*           
9 Common N      no cores   8*             8*             7*             3             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 9
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   0D             2D             1D             2             
5 Legend N-1    T1 cores   2D             5*             1D             2D            
6 Legend N-1    T2 cores   1D             1D             4D             2             
7 Legend N-1    T3 cores   7D             6*             5D             3             
8 Unique N-1    no cores   12*            10*            10*            4             
9 Common N      no cores   6*             5*             5*             2             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 10
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   3              0D             3D             2             
5 Legend N-1    T1 cores   4              2D             4D             2             
6 Legend N-1    T2 cores   7*             5D             5*             3             
7 Legend N-1    T3 cores   7*             5D             5*             3             
8 Unique N-1    no cores   13*            10*            9*             6*            
9 Common N      no cores   4              3              3              2             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

---

## Diagnosis (2026-07-25)

Config 9 (Common N, the INTENDED answer for zone N) per zone:

| Zone | e1 | e2 | e3 | e4 | verdict |
|---|---|---|---|---|---|
| 2 | 17* | 10* | 7* | 5* | OK (tuned) |
| 3 | 17* | 11* | 9* | 5* | OK (tuned) |
| 4 | 5* | 3 | 2 | 4 | only e1 |
| 5 | 9* | 6* | 4 | 8D | dies on e4 |
| 6 | 6* | 5* | 2 | 5* | e3 fails |
| 7 | 6D | 3 | 4 | 2 | DIES on e1 |
| 8 | 8* | 8* | 7* | 3 | e4 fails |
| 9 | 6* | 5* | 5* | 2 | e4 fails |
| 10 | 4 | 3 | 3 | 2 | nothing farms |

**Clean break at Zone 4** — exactly where hand-tuning stopped. This is ONE
systematic mis-calibration, not seven independent ones: after the 3.75x tier
rebase the authored Z4+ enemy stats are sized against a gear assumption that no
longer holds. Z2/Z3 land 5-17 kills; Z4-Z10 land 2-8 on the same 5-kill bar.

### Prescription (do in this order)

1. **Re-calibrate BASE stats Z4-Z10 first — do NOT gate yet.** Target: config 9
   farms all four (>=5 kills, no deaths). Starting point: enemy `hp` x0.65-0.70
   across e1-e4, plus `atk` x0.75 on the deaths (Z5 e4, Z7 e1). Re-run
   `-- --zone=N` after each zone; expect 1-2 passes each once the curve is right.
2. **Then apply the two-axis gate** (proven on Z2/Z3): e3 gets `sustain` pulse
   (MIN-DPS gate — old gear stalls, never dies: idle-rule safe), e4 gets
   `charge_nuke` (EHP gate, telegraphed). Ramp pulse ~9%->20% and nuke ~2.0x->2.9x
   from Z2 to Z10.
3. **Re-verify** `boss_gearcheck` + `boss_threshold` + the 3-seed funnel.

### Hard-won notes

- A blanket scripted trait pass over Z4-Z10 was tried and REVERTED: it made all
  seven worse because the base calibration underneath was already broken. The
  PATTERN transfers between zones; the NUMBERS do not.
- Z1->Z2 has a tighter tuning window than Z2->Z3 (smaller hull tier-1->2 EHP
  gap), so it oscillates - too hard kills the tier-matched Common, too soft lets
  everything farm. Expect the same narrowness at any small hull step.
- Tune with the REAL consumable model: `auto_repair_20` is tier 2 (reachable at
  Z2->Z3) and fires at 20% HP. Modelling 80% flatters every kit and hides deaths.
