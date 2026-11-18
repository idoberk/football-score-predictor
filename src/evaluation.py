import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, brier_score_loss, log_loss

from src.models import make_outcome_model, poisson_probabilities, predict_outcomes


def score_probabilities(
    results: pd.Series, probabilities: pd.DataFrame
) -> dict[str, float]:
    """
    Score predicted outcome probabilities against the actual results.

    Args:
        results (pd.Series): Actual results ("H" / "D" / "A").
        probabilities (pd.DataFrame): One column per result with its predicted
            probability, one row per match (same order as results).

    Returns:
        dict[str, float]: Log loss and Brier score (lower is better), and the
            accuracy of the most likely result (higher is better).
    """
    # sklearn assumes the probability columns are in alphabetical label order (A, D, H).
    # Any other order silently scores the wrong columns
    labels = sorted(probabilities.columns)
    probabilities = probabilities[labels]

    return {
        "log_loss": log_loss(results, probabilities, labels=labels),
        "brier": brier_score_loss(results, probabilities, labels=labels),
        "accuracy": accuracy_score(results, probabilities.idxmax(axis=1)),
    }


def forward_chaining_log_loss(
    matches: pd.DataFrame, features: list[str], validation_seasons: list[int]
) -> pd.Series:
    """
    Score a feature set with season based forward chaining validation.

    For each validation season, the outcome model is trained on all earlier
    seasons and scored on that season.
    This copies real use: Learn from the past, then predict the next season.

    Args:
        matches (pd.DataFrame): Training matches with SeasonStart, FTResult and
            the feature columns.
        features (list[str]): The feature columns to use.
        validation_seasons (list[int]): SeasonStart years to validate on.

    Returns:
        pd.Series: Log loss per validation season.
    """
    log_losses = {}
    for season in validation_seasons:
        earlier = matches[matches["SeasonStart"] < season]
        validation = matches[matches["SeasonStart"] == season]

        model = make_outcome_model().fit(earlier[features], earlier["FTResult"])
        probabilities = predict_outcomes(model, validation, features)
        scores = score_probabilities(validation["FTResult"], probabilities)
        log_losses[season] = scores["log_loss"]

    return pd.Series(log_losses, name="log_loss")


def goal_count_table(goals: pd.Series, rates: np.ndarray, top_bin: int) -> pd.DataFrame:
    """
    Compare how often each number of goals happened with how often a Poisson distribution expects it.

    Args:
        goals (pd.Series): Goals scored by one team, one value per match.
        rates (np.ndarray): Expected goals for that team, one value per match (the
            same value for every match when testing one league wide average).
        top_bin (int): Goal counts from this value up are grouped into one bin
            (for example, 5 means 0, 1, 2, 3, 4, and 5+), so no bin is too small.

    Returns:
        pd.DataFrame: One row per bin with the observed number of matches and the
            expected number under the Poisson distribution.
    """
    # Chance of exactly 0 to top_bin - 1 goals in each match
    probabilities = poisson_probabilities(rates, top_bin - 1)

    # The last bin gets all the remaining probability, so each row sums to 1
    top_bin_probabilities = 1 - probabilities.sum(axis=1, keepdims=True)
    probabilities = np.hstack([probabilities, top_bin_probabilities])

    # Count the matches per bin. clip puts 5, 6, 7, ... goals into the 5+ bin
    observed = np.bincount(goals.clip(upper=top_bin), minlength=top_bin + 1)

    labels = [str(k) for k in range(top_bin)] + [f"{top_bin}+"]

    # Expected matches per bin = the sum of every match's probability for that bin
    return pd.DataFrame(
        {"observed": observed, "expected": probabilities.sum(axis=0)},
        index=pd.Index(labels, name="goals"),
    )
