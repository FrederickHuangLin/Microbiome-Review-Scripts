library(tidyverse)
library(doParallel)
library(foreach)

detectCores()
myCluster = makeCluster(4, type = "FORK")
registerDoParallel(myCluster)

source("data_generation.R")
source("ancom_v2.1.R")

n_taxa = 200; n_samp = 60
x = data.frame(group = paste0("G", rep(1:2, each = n_samp/2))); type = "none"; group = "group"
prop_diff = c(0.05, 0.15, 0.25); zero_prop = 0.2; depth = "small"
meta_data = data.frame(sample_id = paste0("sample", seq(n_samp)), x)

# Set seeds
iterNum = 100
abn_seed = seq(iterNum)

# Define the simulation parameters
simparams = expand.grid(prop_diff, abn_seed)
colnames(simparams) = c("prop_diff", "abn_seed")
simparams = simparams %>% mutate(obs_seed = abn_seed + 1) %>% arrange(prop_diff, abn_seed, obs_seed)
simparams_list = apply(simparams, 1, paste0, collapse = "_")
simparamslabels = c("prop_diff", "abn_seed", "obs_seed")

simlist = foreach(i = simparams_list, .combine = 'cbind', 
                  .packages = c("nlme", "compositions")) %dopar% {
  # i = simparams_list[[1]]
  print(i)
  params = strsplit(i, "_")[[1]]
  names(params) = simparamslabels
  
  # Paras for data generation
  prop_diff = as.numeric(params["prop_diff"])
  abn_seed = as.numeric(params["abn_seed"])
  obs_seed = as.numeric(params["obs_seed"])
  
  # Data generation
  test_dat = abn_tab_gen(n_taxa, n_samp, x, type, group, prop_diff,
                         abn_seed, obs_seed, zero_prop, depth)
  obs_abn = test_dat$obs_abn
  
  # Run ANCOM-BC
  feature_table = obs_abn; sample_var = "sample_id"; group_var = "group"
  out_cut = 0; zero_cut = 0.90; lib_cut = 0; neg_lb = FALSE
  prepro = feature_table_pre_process(feature_table, meta_data, sample_var, group_var, 
                                     out_cut, zero_cut, lib_cut, neg_lb)
  feature_table = prepro$feature_table # Preprocessed feature table
  meta_data = prepro$meta_data # Preprocessed metadata
  struc_zero = prepro$structure_zeros # Structural zero info
  
  main_var = "group"; p_adj_method = "holm"; alpha = 0.05
  adj_formula = NULL; rand_formula = NULL
  out = ANCOM(feature_table, meta_data, struc_zero, main_var, p_adj_method, 
              alpha, adj_formula, rand_formula)
  
  res_test = out$out$detected_0.7 * 1
  res_true = test_dat$diff_ind * 1
  res_true[test_dat$zero_ind] = 1
  res_true = res_true[rownames(feature_table)]
  TP = sum(res_test[res_true == 1] == 1, na.rm = T)
  FP = sum(res_test[res_true == 0] == 1, na.rm = T)
  FN = sum(res_test[res_true == 1] == 0, na.rm = T)
  FDR = FP/(TP + FP); power = TP/(TP + FN)
  c(FDR, power)
}

stopCluster(myCluster)
write_csv(data.frame(simlist), "sim_fdr_power_ancom.csv")
