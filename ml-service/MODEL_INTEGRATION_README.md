# XDR Model Integration README

This repo integrates the trained run-level DoS/DDoS detector into `ml-service`.
The service now keeps the original keyword demo classifier as a fallback for
non-DDoS scenarios, and uses the trained EBM detector when DDoS-like telemetry
or raw run-level rows are submitted.

## Integrated Artifacts

- Teacher models: `ml-service/models/teachers/`
- EBM surrogate models: `ml-service/models/surrogates/`
- Metrics and label metadata: `ml-service/models/metadata/`
- Global explanation plots: `frontend/public/model-explanations/`

## Service Endpoints

- `GET /health`: service health plus loaded trained model status.
- `GET /models`: all EBM/teacher/surrogate model cards and plot paths.
- `POST /predict-event`: existing XDR event contract, EBM-backed for DDoS candidates.
- `POST /analyze-window`: existing XDR window contract, EBM-backed for DDoS windows.
- `POST /predict-run`: raw CSV-style run-level row prediction with native EBM explanation.
- `POST /predict-run/{model_name}`: raw row prediction for `ebm`, `xgboost`, `random_forest`, `svm`, or `mlp`.
- `POST /predict-run-csv/{model_name}`: same prediction contract from a text/csv request body.

The XDR response includes `explanation_features`, which are produced by the
native EBM for `ebm` and by the corresponding EBM surrogate for each teacher.
The backend persists these explanation features on predictions and incidents so
they can be displayed in incident detail views.

# Training Bundle README

This folder contains the full modelling, explanation, surrogate, plotting, and API bundle for the Coding Fest 2026 XDR DoS/service-stress dataset.

## Dataset

Source dataset:

```text
model-ready/training-batch-20260607T132426Z-model-ready-run-level.csv
```

Training target:

```text
main_label
```

Task:

```text
Binary classification: Benign vs DoS_DDoS
```

Rows used:

- Raw model-ready rows: 300
- Clean supervised rows after filtering `is_clean_supervised_training_candidate == True`: 299
- Split: 70/10/20 stratified train/validation/test
- Train rows: 209
- Validation rows: 30
- Test rows: 60

## Feature Processing

The pipeline drops leakage-prone, generator/setup, constant, duplicate, and low-value fields before training.

Retained base features:

- `request_completed_count`
- `request_rate_per_second`
- `peak_request_rate_per_second`
- `unique_path_count`
- `repeated_path_count`
- `search_query_count`
- `avg_response_time_ms`
- `max_response_time_ms`
- `p95_response_time_ms`
- `health_check_count`
- `avg_health_check_latency_ms`
- `max_health_check_latency_ms`

Engineered features:

- `request_repeat_ratio`
- `search_request_ratio`
- `health_check_ratio`
- `latency_spread_ms`
- `p95_avg_latency_ratio`

No categorical predictors remain after pruning, but the training code supports label encoding if categorical predictors are present.

## Training Scripts

- `train_models.py`: trains XGBoost, EBM, Random Forest, SVM, and MLP with grid search.
- `ebm_global_and_surrogates.py`: plots the original EBM and trains EBM surrogates for non-EBM teacher models.
- `api_service.py`: FastAPI service for predictions and feature-importance explanations.

## Main Model Results

Test split results:

| Model | Accuracy | Precision | Recall | F1 | ROC AUC |
|---|---:|---:|---:|---:|---:|
| EBM | 0.9500 | 0.9302 | 1.0000 | 0.9639 | 0.9975 |
| XGBoost | 0.9500 | 0.9302 | 1.0000 | 0.9639 | 0.9900 |
| Random Forest | 0.9500 | 0.9302 | 1.0000 | 0.9639 | 0.9813 |
| SVM | 0.9000 | 0.8696 | 1.0000 | 0.9302 | 0.9863 |
| MLP | 0.8167 | 0.7959 | 0.9750 | 0.8764 | 0.8675 |

Best overall model by validation F1:

```text
EBM
```

## Best Model Artifacts

Saved tuned models:

```text
best_models/ebm_best_model.joblib
best_models/xgboost_best_model.joblib
best_models/random_forest_best_model.joblib
best_models/svm_best_model.joblib
best_models/mlp_best_model.joblib
best_models/best_overall_model_by_val_f1.joblib
```

Grid-search objects and encoders:

```text
artifacts/models/
```

Metrics, predictions, classification reports, confusion matrices, ROC plots, and feature importances:

```text
artifacts/results/
```

EDA artifacts:

```text
artifacts/eda/
```

Notebook report:

```text
model_training_report.ipynb
```

## EBM Global Explanation

Original EBM global plots are saved in:

```text
plots_ebm/
```

This folder contains:

- `original_ebm_global_feature_importance.png`
- `original_ebm_global_feature_importance.csv`
- top EBM shape plots under `plots_ebm/main_effect_terms/`
- matching CSV exports for each plotted main effect

## Surrogate Models

For each non-EBM teacher model, an EBM surrogate was trained using pseudo-labels from the teacher.

Synthetic surrogate-training data:

- 1000 local perturbation samples
- 500 VAE samples
- VAE latent dimension: 2
- Total: 1500 synthetic samples per teacher
- Synthetic values clipped to processed training feature min/max ranges

Surrogate model artifacts:

```text
artifacts/surrogates/models/ebm_surrogate_for_xgboost.joblib
artifacts/surrogates/models/ebm_surrogate_for_random_forest.joblib
artifacts/surrogates/models/ebm_surrogate_for_svm.joblib
artifacts/surrogates/models/ebm_surrogate_for_mlp.joblib
```

Synthetic data and pseudo-label training CSVs:

```text
artifacts/surrogates/synthetic/
```

Full surrogate report:

```text
artifacts/surrogates/surrogate_fidelity_error_report.json
artifacts/surrogates/surrogate_fidelity_error_summary.csv
artifacts/surrogates/SURROGATE_SUMMARY.md
```

## Surrogate Fidelity Results

| Teacher | EBM Surrogate Test Fidelity Accuracy | Test Fidelity F1 | Error Fidelity Accuracy | Error Fidelity F1 |
|---|---:|---:|---:|---:|
| Random Forest | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
| XGBoost | 0.9833 | 0.9885 | 1.0000 | 1.0000 |
| SVM | 0.9500 | 0.9663 | 0.5000 | 0.6667 |
| MLP | 0.9000 | 0.9362 | 0.4545 | 0.6250 |

Error fidelity follows the CSS2 project definition: evaluate surrogate-vs-teacher fidelity only on real test rows where the teacher is wrong against the true label. Because this dataset has only 60 test rows, teacher-error subsets are small and high-variance.

## Surrogate Plot Folders

Convenience folders for each teacher-aligned EBM surrogate:

```text
plots_surrogates/xgboost/
plots_surrogates/random_forest/
plots_surrogates/svm/
plots_surrogates/mlp/
```

Each folder contains:

- surrogate global feature importance PNG
- surrogate global feature importance CSV
- top surrogate main-effect shape plots
- matching shape CSV files

The original generated plot source folders are also retained under:

```text
artifacts/surrogates/plots/
```

## FastAPI Service

Start the API:

```powershell
uvicorn train.api_service:app --host 127.0.0.1 --port 8000
```

Health and metadata:

```text
GET /health
GET /features
GET /models
```

Default EBM prediction endpoints:

```text
POST /predict
POST /predict_csv
```

Model-specific prediction endpoints:

```text
POST /predict/ebm
POST /predict/xgboost
POST /predict/random_forest
POST /predict/svm
POST /predict/mlp

POST /predict_csv/ebm
POST /predict_csv/xgboost
POST /predict_csv/random_forest
POST /predict_csv/svm
POST /predict_csv/mlp
```

For `ebm`, the EBM is both the teacher model and explanation model.

For `xgboost`, `random_forest`, `svm`, and `mlp`, the teacher model makes the prediction and the attached EBM surrogate provides:

- surrogate global feature importance
- surrogate local feature contributions
- surrogate prediction
- teacher-surrogate agreement flag

## JSON API Example

```powershell
$row = Import-Csv model-ready\training-batch-20260607T132426Z-model-ready-run-level.csv | Select-Object -First 1
$body = $row | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/predict/xgboost?top_n=10" -ContentType "application/json" -Body $body
```

## CSV API Example

```powershell
$csv = Get-Content model-ready\training-batch-20260607T132426Z-model-ready-run-level.csv -Raw
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/predict_csv/random_forest?top_n=10" -ContentType "text/csv" -Body $csv
```

## API Response Shape

Each prediction response includes:

- `teacher_predicted_label`
- `teacher_probabilities`
- `surrogate_predicted_label`
- `teacher_surrogate_match`
- `processed_features`
- `surrogate_local_feature_importance`
- `surrogate_global_feature_importance`

## Caveats

This is a controlled lab-generated Wazuh-linked DoS/service-stress dataset. The modelling and surrogate results are suitable for a proof-of-concept and explanation workflow, but should not be treated as production-grade DDoS evidence without validation on an independent batch.
