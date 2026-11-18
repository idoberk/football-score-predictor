# La Liga Match Prediction

Predicting the result of Spanish La Liga matches from 25 seasons of match history. For every
match the model gives the chance of a home win, a draw and an away win, plus the most likely
score:

> **Real Madrid 46% / Draw 22% / Barcelona 32%, most likely 1-1 (12%)**

The project is a proof of concept for the "prediction engine". It was built as a solo 2 day hackathon project for the Developers Institute _AI Powered Data Analytics_ bootcamp, and covers the full workflow: data cleaning, exploratory analysis, an Excel analysis workbook, and simple machine learning models that are compared honestly against the bookmakers.

---

## Highlights

- **Home advantage is real:** Home teams win 47.2% of La Liga matches, away teams 27.7%. In
  2020/21, played in empty stadiums because of COVID, home wins fell to 41.6%, the lowest of all
  seasons.
- **Two clubs dominate:** Barcelona (13) and Real Madrid (8) won 21 of the 25 titles.
- **Upsets are common:** The bookmakers' underdog wins about 1 match in 5 (20.8%).
- **The model comes very close to the bookmakers:** On the 2025/26 test season its log loss is
  0.9667 against the bookmakers' 0.9637. It closes 96% of the gap between "knowing nothing about
  the teams" and the bookmakers.
- **Its confidence is honest:** When the model gives a result about 70%, it happens about 70% of
  the time.

---

## Data

[xgabora/Club-Football-Match-Data](https://github.com/xgabora/Club-Football-Match-Data) (MIT
license): about 239,000 matches from 38 divisions, 2000/01 to early 2026/27, plus club Elo
ratings.

- The project keeps **La Liga** (`SP1`) and **Segunda División** (`SP2`). Segunda gives newly
  promoted teams a match history before they reach La Liga.
- **Used columns:** Date, teams, full time score and result, both teams' Elo rating, recent form,
  match stats (shots, shots on target, corners, cards) and Bet365 odds.
- **Analysis set:** 9,388 La Liga matches from complete seasons (2000/01 to 2025/26).

**Data quality issues found and handled:**

- 2006/07 is missing from the source, and 2004/05 has only 268 of its 380 La Liga matches.
- Match stats exist only from 2005/06 in La Liga and from 2017/18 in Segunda.
- Elo ratings after June 2025 are the dataset's own continuation, not official ClubElo ratings.
- The `C_*` cluster columns may be derived from match stats, so they were dropped to avoid
  leakage.
- Team names are made consistent across seasons (for example `Leonesa` → `Cultural Leonesa`).

**Fixtures and current results:** The [football-data.org](https://www.football-data.org) API (free
tier) gives the full 2026/27 La Liga schedule with kickoff times, and the results of the matches
played so far. One request returns the whole season (380 matches). The raw JSON is saved locally
and the matches are stored in the `fixtures` table in PostgreSQL.

- API teams are matched to the dataset's teams by the API's numeric team id, not by name (only 9
  of the 20 short names are the same). All 31 matches that are in both sources agree on the date
  and the score.
- The API sends a 0-0 score for a cancelled match. It's a placeholder, so goals are stored only
  for finished matches.
- The dataset ends on 3 September 2026. The API has 88 more finished La Liga matches after that
  date (results only, no match stats or Elo).

---

## Approach

Everything runs in one notebook, [`notebooks/laliga_match_prediction.ipynb`](notebooks/laliga_match_prediction.ipynb),
with reusable code in [`src/`](src/).

1. **Profile and clean:** Shape, types, missing values by season, duplicates, and checks that the
   data is consistent (for example that every result matches its score).
2. **Exploratory analysis:** Home advantage over time, goals per season, results by Elo
   difference, and the dominance of Real Madrid and Barcelona.
3. **Excel export:** The cleaned matches and league tables go to `outputs/laliga_data.xlsx`, which
   is the starting point of the hand built Excel analysis.
4. **Features, without data leakage:** A feature may only use information known before kickoff.
    - The dataset's Elo and Form columns were tested and confirmed to be taken before the match.
    - Rolling averages over each team's previous 10 La Liga matches: goals for and against, and
      shots on target for and against. `shift(1)` before `rolling()` keeps a match out of its own
      feature.
    - Promoted teams look much stronger in Segunda than in La Liga, so until they have 5 La Liga
      matches they get the average values of past promoted teams.
5. **Split by time:** Train on 2007/08 to 2024/25 (6,840 matches), test on 2025/26 (380 matches),
   a season the model never saw. Features were chosen with forward chaining validation over
   2015/16 to 2024/25: Each season is scored by a model trained only on the seasons before it.
6. **Models:**
    - **Baselines first:** A uniform guess, always home win, and the result shares of the
      training seasons.
    - **Outcome model:** Multinomial logistic regression (home win / draw / away win) on the Elo
      difference and the four shots on target averages. Simple, fast, and every weight can be read.
    - **Score model:** Two Poisson regressions, for home goals and away goals. They give a 9×9
      table of score chances, from which come the most likely score and a second set of
      home win / draw / away win chances.
    - **Benchmark:** The bookmakers' odds, turned into probabilities with their margin removed.
      They are used only for comparison, never as a model input.
7. **Evaluation:** Log loss and Brier score (they measure the quality of the probabilities),
   accuracy, a confusion matrix, a calibration chart, train vs test scores, and Real Madrid or
   Barcelona matches vs all others.
8. **Example predictions:** All 349 remaining pairings of the 2026/27 season. The dataset has no
   future fixtures, so they are built as "every team plays every other team at home and away,
   minus the matches already played".

---

## Results (test season 2025/26)

| Model                          | Log loss ↓ | Brier score ↓ | Accuracy  |
| ------------------------------ | ---------- | ------------- | --------- |
| Uniform (1/3 each)             | 1.0986     | 0.6667        | 26.6%     |
| Always home win                | 18.4012    | 1.0211        | 48.9%     |
| Training result shares         | 1.0473     | 0.6306        | 48.9%     |
| **Logistic regression**        | **0.9667** | **0.5722**    | **53.2%** |
| Poisson (from the score table) | 0.9683     | 0.5740        | 52.9%     |
| Bookmaker (Bet365)             | 0.9637     | 0.5710        | 54.5%     |

- **Why log loss and not only accuracy:** Accuracy only checks the top pick. Draws are about 25%
  of matches but almost never the single most likely result, so accuracy hides how good the
  probabilities are. Log loss rewards giving the real result a high chance.
- **No overfitting:** Log loss is 0.9675 on the training seasons and 0.9667 on the test season.
- **Elo is the strongest feature:** Each 100 Elo points in favor of the home team add about 11
  percentage points to its win chance. Between equal teams, the home team still wins 47% of the
  time. Shots on target add a little on top of Elo (validation log loss 0.9778 vs 0.9814 for Elo
  alone), while recent form and rolling goals add nothing.
- **Draws:** Neither the model nor the bookmakers ever pick a draw as the top result. Still, the
  model's average draw chance (24.7%) is almost exactly the real draw share (24.5%).
- **Big clubs are easier:** Matches with Real Madrid or Barcelona have a log loss of 0.69,
  against 1.03 for all other matches.
- **Exact scores are hard:** The most likely score has on average a 12.5% chance, and it was the
  real score in 15.3% of matches (58 of 380). That's why the headline number is the result
  chance, not the score.

<p align="center">
  <img src="outputs/figures/calibration_test_season.png" alt="Calibration of the model on the 2025/26 season" width="48%">
  <img src="outputs/figures/home_advantage_by_season.png" alt="Home advantage in La Liga by season" width="48%">
</p>

---

## Excel analysis

The notebook writes the data to [`outputs/laliga_data.xlsx`](outputs/laliga_data.xlsx). All the
analysis in [`outputs/laliga_analysis.xlsx`](outputs/laliga_analysis.xlsx) was built by hand in
Microsoft 365 Excel, so re-running the notebook never overwrites it.

| Sheet             | What it shows                                                              | Excel skills                                                                    |
| ----------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `Matches`         | 9,388 matches with upsets highlighted                                      | Tables, calculated columns, `IF` / `AND` / `OR`, conditional formatting         |
| `SeasonSummary`   | Goals and results per season, with two line charts and 2020/21 highlighted | `UNIQUE`, `COUNTIFS`, `AVERAGEIFS`, `MEDIAN(FILTER)`, color scale               |
| `Upsets`          | How often the underdog wins, and the biggest shocks                        | `COUNTIFS`, `MAXIFS`, `XLOOKUP`, `FILTER`                                       |
| `PivotResults`    | Result shares by season                                                    | Pivot table, % of row total                                                     |
| `PivotTeams`      | Goals for and against per club                                             | Pivot table, calculated field, slicer                                           |
| `PivotTitles`     | Titles per club                                                            | Pivot table, report filter, pivot chart                                         |
| `TeamLookup`      | A team and season card driven by dropdowns                                 | Data validation, `XLOOKUP` with two keys and two directions, `SUMIFS`, `MINIFS` |
| `TestPredictions` | The model's 2025/26 predictions next to the real results                   | Calculated columns, `XLOOKUP`, `IFS`, data bars                                 |
| `Predictions`     | Model vs bookmakers, confidence vs hit rate, the biggest surprises         | `COUNTIFS`, `AVERAGEIFS`, `SORTBY` / `TAKE` / `HSTACK`, chart                   |

---

## Project structure

```
football-score-predictor/
├── environment.yml            # Conda environment with pinned versions
├── data/
│   ├── raw/                   # Matches.csv, EloRatings.csv and the API's JSON (not in the repo)
│   └── processed/             # Cleaned La Liga and Segunda matches
├── notebooks/
│   ├── database_load.ipynb             # Loads the cleaned data into PostgreSQL
│   ├── fixtures_api.ipynb              # Fetches fixtures from the API and upserts them
│   └── laliga_match_prediction.ipynb   # The main notebook
├── sql/
│   ├── 01_create_database.sql         # Owner role and database
│   ├── 02_create_tables.sql           # Tables, keys and constraints
│   ├── 03_analysis_queries.sql        # League table, rolling shots on target, bookmakers
│   ├── 04_roles_and_privileges.sql    # Read only analyst and pipeline roles
│   ├── 05_create_fixtures.sql         # Fixtures table for the API matches
│   └── 06_fixtures_queries.sql        # Next fixtures, API vs dataset, half time from JSONB
├── src/
│   ├── cleaning.py            # Profiling helpers, season columns, league tables
│   ├── team_names.py          # Team name fixes
│   ├── plotting.py            # Shared chart helpers
│   ├── features.py            # Rolling features without leakage
│   ├── models.py              # Logistic and Poisson models, score tables, bookmaker probabilities
│   └── evaluation.py          # Scoring and forward chaining validation
└── outputs/
    ├── figures/               # Charts saved by the notebook
    ├── laliga_data.xlsx       # Data exported by the notebook
    └── laliga_analysis.xlsx   # Hand built Excel analysis
```

---

## How to run

1. **Clone the repo:**
    ```bash
    git clone https://github.com/idoberk/football-score-predictor.git
    cd football-score-predictor
    ```
2. **Create the environment** (needs [Miniconda](https://docs.conda.io/en/latest/miniconda.html)
   or Anaconda):
    ```bash
    conda env create -f environment.yml
    conda activate laliga-prediction
    ```
3. **Get the data:** Download `Matches.csv` and `EloRatings.csv` from
   [xgabora/Club-Football-Match-Data](https://github.com/xgabora/Club-Football-Match-Data) and put
   them in `data/raw/`. The raw files are about 57 MB, so they are not stored in this repo.
4. **Run the notebook:** Open `notebooks/laliga_match_prediction.ipynb` in VS Code or Jupyter,
   select the `laliga-prediction` kernel, and run all cells.
5. **Set up the database (optional, for the PostgreSQL part):** Needs a local PostgreSQL
   server (built and tested with PostgreSQL 18). From the repo root:
    ```bash
    # As the postgres superuser: The project's owner role and database
    psql -U postgres -d postgres -f sql/01_create_database.sql
    ```
   Set the owner's password: Open `psql -U postgres -d postgres` and run
   `\password football_admin`. Then:
    ```bash
    # As the owner: Tables, keys and constraints
    psql -U football_admin -d football_predictor -f sql/02_create_tables.sql
    # As the superuser: Read only and pipeline roles (ends with a privilege check)
    psql -U postgres -d football_predictor -f sql/04_roles_and_privileges.sql
    ```
   Set passwords for `analyst_user` and `pipeline_app` the same way with `\password`. Then
   create the fixtures table (after `04`, so the analyst role can read it automatically):
    ```bash
    # As the owner: Fixtures table, writable by the pipeline role
    psql -U football_admin -d football_predictor -f sql/05_create_fixtures.sql
    ```
   Create a `.env` file in the repo root (it is git ignored, never commit it):
    ```
    PGHOST=localhost
    PGPORT=5432
    PGDATABASE=football_predictor
    PGUSER=football_admin
    PGPASSWORD=your_password
    PIPELINE_PGUSER=pipeline_app
    PIPELINE_PGPASSWORD=pipeline_app_password
    FOOTBALL_DATA_API=your_api_key
    ```
   Run `notebooks/database_load.ipynb` to load the data. It empties and reloads the tables, so
   it can be run again at any time. Example queries are in `sql/03_analysis_queries.sql`.
6. **Fetch the fixtures (optional, needs step 5):** Register for a free API key at
   [football-data.org](https://www.football-data.org/client/register) and put it in `.env` as
   `FOOTBALL_DATA_API`. Then run `notebooks/fixtures_api.ipynb`. It makes one API request,
   saves the JSON in `data/raw/football_data/` and upserts the matches into `fixtures` as
   `pipeline_app`, so it can be run again at any time to get new results and kickoff times.
   Example queries are in `sql/06_fixtures_queries.sql`.

The analysis workbook needs Microsoft 365 or Excel 2021 or later (for `XLOOKUP`, `FILTER`,
`UNIQUE` and the other dynamic array functions).

---

## Limitations

- **Football is random.** Even the bookmakers pick the right result only about 55% of the time.
- **Draws are hard to predict.** They are about a quarter of all matches but rarely the most
  likely result.
- **No expected goals (xG).** No historical xG source was both accessible and allowed to be
  scraped, so rolling shots on target is used as a simpler stand in.
- **Elo after June 2025 is provisional**, and 2006/07 is missing from the data.
- **No lineups, injuries or transfers.** The bookmakers know all of these, which is the main
  reason they stay slightly ahead.
- **The 2026/27 pairings have no dates**, so every prediction uses the team ratings as they were
  at the last available data point (Elo snapshot of 1 September 2026).

---

## Credits

- Data: [xgabora/Club-Football-Match-Data](https://github.com/xgabora/Club-Football-Match-Data)
  (MIT license), which also includes Elo ratings based on [ClubElo](http://clubelo.com).
- Fixtures and current results: Football data provided by the
  [Football-Data.org](https://www.football-data.org) API.
