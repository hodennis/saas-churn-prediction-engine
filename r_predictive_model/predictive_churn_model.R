library(DBI)
library(RPostgres)
library(tidyverse)
library(tidymodels)
library(ranger)
library(vip)

con <- dbConnect(RPostgres::Postgres(),
                 host = Sys.getenv("DB_HOST"), port = Sys.getenv("DB_PORT"),
                 dbname = Sys.getenv("DB_NAME"), user = Sys.getenv("DB_USER")
)

accounts <- dbGetQuery(con, "SELECT account_id, industry, status FROM accounts;")

telemetry <- dbGetQuery(con, "
  SELECT account_id, mrr_amount, total_logins_30d, active_users, features_used, support_tickets
  FROM account_telemetry
  WHERE report_month = (SELECT MAX(report_month) FROM account_telemetry);
")

final_model_dataset <- accounts %>%
  inner_join(telemetry, by = "account_id") %>%
  mutate(
    # The SQL script already defined who churned. We map it for the ML engine here.
    churn_risk = as.factor(ifelse(status == 'Churned', "High", "Low")),
    industry = as.factor(industry)
  )

# Strip identifiers, raw status, and MRR (to prevent target leakage) from the algorithm
model_df <- final_model_dataset %>%
  select(-account_id, -status, -mrr_amount) %>%
  drop_na()

# Data Splitting (80% Training / 20% Testing)
set.seed(2026) # Critical for reproducibility 
data_split <- initial_split(model_df, prop = 0.80, strata = churn_risk)
train_data <- training(data_split)
test_data  <- testing(data_split)



churn_rec <- recipe(churn_risk ~ ., data = train_data) %>%
  step_zv(all_predictors()) %>% # Removes zero-variance columns
  step_dummy(all_nominal_predictors()) %>% # One-hot encodes the 'industry' text
  step_normalize(all_numeric_predictors()) # Scales numeric features

rf_spec <- rand_forest(trees = 500, mtry = 3) %>%
  set_engine("ranger", importance = "permutation") %>%
  set_mode("classification")

churn_wf <- workflow() %>%
  add_recipe(churn_rec) %>%
  add_model(rf_spec)

rf_fit <- churn_wf %>% fit(data = train_data)

# This generates the plot proving 'total_logins_30d' is the biggest behavioral driver
rf_fit %>% 
  extract_fit_parsnip() %>% 
  vip(geom = "point") + 
  theme_minimal() +
  labs(title = "Drivers of SaaS Churn Risk")



predictions <- predict(rf_fit, test_data) %>%
  bind_cols(predict(rf_fit, test_data, type = "prob")) %>%
  bind_cols(test_data)

# Calculate the ROC AUC Score
roc_score <- roc_auc(predictions, truth = churn_risk, .pred_High)
print(paste("Model ROC AUC Score:", round(roc_score$.estimate, 3)))

# Predict on the ENTIRE dataset to push back to the BI tool
all_predictions <- predict(rf_fit, final_model_dataset, type = "prob") %>%
  bind_cols(final_model_dataset %>% select(account_id)) %>%
  mutate(risk_tier = ifelse(.pred_High > 0.75, "Critical Risk", 
                            ifelse(.pred_High > 0.50, "Elevated Risk", "Safe"))) %>%
  select(account_id, churn_probability = .pred_High, risk_tier)

dbWriteTable(
  con, 
  name = "churn_predictions", 
  value = all_predictions, 
  overwrite = TRUE, 
  row.names = FALSE
)

dbDisconnect(con)
cat("Predictions successfully exported to PostgreSQL. \n")
