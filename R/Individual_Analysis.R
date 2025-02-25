#' Individual-variant analysis using score test for whole-genome sequencing data
#'
#' The \code{Individual_Analysis} function takes in chromosome, starting location, ending location,
#' the object of opened annotated GDS file, and the object from fitting the null model to analyze the association between a
#' quantitative/dichotomous phenotype and each individual variant in a genetic region by using score test.
#' @param chr chromosome.
#' @param start_loc starting location (position) of the genetic region for each individual variant to be analyzed using score test.
#' @param end_loc ending location (position) of the genetic region for each individual variant to be analyzed using score test.
#' @param genofile an object of opened annotated GDS (aGDS) file.
#' @param obj_nullmodel an object from fitting the null model, which is either the output from \code{fit_nullmodel} function,
#' or the output from \code{fitNullModel} function in the \code{GENESIS} package and transformed using the \code{genesis2staar_nullmodel} function.
#' @param mac_cutoff the cutoff of minimum minor allele count in
#' defining individual variants (default = 20).
#' @param subset_variants_num the number of variants to run per subset for each time (default = 5e3).
#' @param QC_label channel name of the QC label in the GDS/aGDS file (default = "annotation/filter").
#' @param variant_type variants include in the analysis. Choices include "variant", "SNV", or "Indel" (default = "variant").
#' @param geno_missing_imputation method of handling missing genotypes. Either "mean" or "minor" (default = "mean").
#' @return a data frame containing the score test p-value and effect size for each individual variant in the given genetic region.
#' @references Chen, H., et al. (2016). Control for population structure and relatedness for binary traits
#' in genetic association studies via logistic mixed models. \emph{The American Journal of Human Genetics}, \emph{98}(4), 653-666.
#' (\href{https://doi.org/10.1016/j.ajhg.2016.02.012}{pub})
#' @export

Individual_Analysis <- function(chr,start_loc,end_loc,genofile,obj_nullmodel,mac_cutoff=20,subset_variants_num=5e3,
                                QC_label="annotation/filter",variant_type=c("variant","SNV","Indel"),geno_missing_imputation=c("mean","minor")){

	## evaluate choices
	variant_type <- match.arg(variant_type)
	geno_missing_imputation <- match.arg(geno_missing_imputation)

	## Null Model
	phenotype.id <- as.character(obj_nullmodel$id_include)

	samplesize <- length(phenotype.id)

	### dense GRM
	if(!obj_nullmodel$sparse_kins)
	{
        P <- obj_nullmodel$P
        P_scalar <- sqrt(dim(P)[1])
        P <- P*P_scalar

		residuals.phenotype <- obj_nullmodel$scaled.residuals
        residuals.phenotype <- residuals.phenotype*sqrt(P_scalar)
	}

	### sparse GRM
	if(obj_nullmodel$sparse_kins)
	{
		Sigma_i <- obj_nullmodel$Sigma_i
		Sigma_iX <- as.matrix(obj_nullmodel$Sigma_iX)
		cov <- obj_nullmodel$cov

		residuals.phenotype <- obj_nullmodel$scaled.residuals
	}

	## get SNV id
	filter <- seqGetData(genofile, QC_label)
	if(variant_type=="variant")
	{
		SNVlist <- filter == "PASS"
	}

	if(variant_type=="SNV")
	{
		SNVlist <- (filter == "PASS") & isSNV(genofile)
	}

	if(variant_type=="Indel")
	{
		SNVlist <- (filter == "PASS") & (!isSNV(genofile))
	}

	position <- as.numeric(seqGetData(genofile, "position"))

	variant.id <- seqGetData(genofile, "variant.id")
	is.in <- (SNVlist)&(position>=start_loc)&(position<=end_loc)
	SNV.id <- variant.id[is.in]

	subset.num <- ceiling(length(SNV.id)/subset_variants_num)

	results <- c()

	if(subset.num == 0)
	{
	  return(results)
	}

	for(kk in 1:subset.num)
	{
		if(kk < subset.num)
		{
			is.in <- ((kk-1)*subset_variants_num+1):(kk*subset_variants_num)
			seqSetFilter(genofile,variant.id=SNV.id[is.in],sample.id=phenotype.id)
		}
		if(kk == subset.num)
		{
			is.in <- ((kk-1)*subset_variants_num+1):length(SNV.id)
			seqSetFilter(genofile,variant.id=SNV.id[is.in],sample.id=phenotype.id)
		}

		## genotype id
		id.genotype <- seqGetData(genofile,"sample.id")

		id.genotype.merge <- data.frame(id.genotype,index=seq(1,length(id.genotype)))
		phenotype.id.merge <- data.frame(phenotype.id)
		phenotype.id.merge <- dplyr::left_join(phenotype.id.merge,id.genotype.merge,by=c("phenotype.id"="id.genotype"))
		id.genotype.match <- phenotype.id.merge$index


		Geno <- seqGetData(genofile, "$dosage")
		Geno <- Geno[id.genotype.match,,drop=FALSE]

		if(geno_missing_imputation=="mean")
		{
			Geno <- matrix_flip_mean(Geno)
		}
		if(geno_missing_imputation=="minor")
		{
			Geno <- matrix_flip_minor(Geno)
		}

		MAF <- Geno$MAF
		ALT_AF <- 1 - Geno$AF

		CHR <- as.numeric(seqGetData(genofile, "chromosome"))
		position <- as.numeric(seqGetData(genofile, "position"))
		REF <- as.character(seqGetData(genofile, "$ref"))
		ALT <- as.character(seqGetData(genofile, "$alt"))
		N <- rep(samplesize,length(CHR))

		if(sum(MAF>=0.05)>=1)
		{
		  ## Common_variants
		  Geno_common <- Geno$Geno[,MAF>=0.05]

		  CHR_common <- CHR[MAF>=0.05]
		  position_common <- position[MAF>=0.05]
		  REF_common <- REF[MAF>=0.05]
		  ALT_common <- ALT[MAF>=0.05]
		  MAF_common <- MAF[MAF>=0.05]
		  ALT_AF_common <- ALT_AF[MAF>=0.05]
		  N_common <- N[MAF>=0.05]

		  if(sum(MAF>=0.05)==1)
		  {
		    Geno_common <- as.matrix(Geno_common,ncol=1)
		  }

		  ## sparse GRM
		  if(obj_nullmodel$sparse_kins)
		  {
			Score_test <- Individual_Score_Test(Geno_common, Sigma_i, Sigma_iX, cov, residuals.phenotype)
		  }

		  ## dense GRM
		  if(!obj_nullmodel$sparse_kins)
		  {
			Score_test <- Individual_Score_Test_denseGRM(Geno_common, P, residuals.phenotype)
		  }

		  results_temp <- data.frame(CHR=CHR_common,POS=position_common,REF=REF_common,ALT=ALT_common,ALT_AF=ALT_AF_common,MAF=MAF_common,N=N_common,
						pvalue=exp(-Score_test$pvalue_log),pvalue_log10=Score_test$pvalue_log/log(10),
						Score=Score_test$Score,Score_se=Score_test$Score_se,
						Est=Score_test$Est,Est_se=Score_test$Est_se)

		  results <- rbind(results,results_temp)
		}

		## Rare_variants
		if(sum((MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05))>=1)
		{
		  Geno_rare <- Geno$Geno[,(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]

		  CHR_rare <- CHR[(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]
		  position_rare <- position[(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]
		  REF_rare <- REF[(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]
		  ALT_rare <- ALT[(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]
		  MAF_rare <- MAF[(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]
		  ALT_AF_rare <- ALT_AF[(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]
		  N_rare <- N[(MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05)]

		  ## sparse GRM
		  if(obj_nullmodel$sparse_kins)
		  {
			if(sum((MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05))>=2)
			{
				Geno_rare <- as(Geno_rare,"dgCMatrix")
				Score_test <- Individual_Score_Test_sp(Geno_rare, Sigma_i, Sigma_iX, cov, residuals.phenotype)
			}else
			{
				Geno_rare <- as.matrix(Geno_rare,ncol=1)
				Score_test <- Individual_Score_Test(Geno_rare, Sigma_i, Sigma_iX, cov, residuals.phenotype)
			}
          }

		  ## dense GRM
		  if(!obj_nullmodel$sparse_kins)
		  {
			if(sum((MAF>(mac_cutoff-0.5)/samplesize/2)&(MAF<0.05))>=2)
			{
				Geno_rare <- as(Geno_rare,"dgCMatrix")
				Score_test <- Individual_Score_Test_sp_denseGRM(Geno_rare, P, residuals.phenotype)
			}else
			{
				Geno_rare <- as.matrix(Geno_rare,ncol=1)
				Score_test <- Individual_Score_Test_denseGRM(Geno_rare, P, residuals.phenotype)
			}
		  }

		  results_temp <- data.frame(CHR=CHR_rare,POS=position_rare,REF=REF_rare,ALT=ALT_rare,ALT_AF=ALT_AF_rare,MAF=MAF_rare,N=N_rare,
						pvalue=exp(-Score_test$pvalue_log),pvalue_log10=Score_test$pvalue_log/log(10),
						Score=Score_test$Score,Score_se=Score_test$Score_se,
						Est=Score_test$Est,Est_se=Score_test$Est_se)

		  results <- rbind(results,results_temp)
		}

		seqResetFilter(genofile)
	}

	if(!is.null(results))
	{
	  results <- results[order(results[,2]),]
	}

	return(results)
}

