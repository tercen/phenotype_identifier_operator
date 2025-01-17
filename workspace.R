library(tercen)
library(dplyr)
library(tidyr)
library(stringr)

#library(flowCore)
#library(FlowSOM)
#library(MEM)
#library(tictoc)

#options("tercen.workflowId" = "f119a84e79d66805c986d2fe4c0a1164")
options("tercen.workflowId" = "9af47f50c3160717a5378977da00e254")

#options("tercen.stepId"     = "3bbf5208-96b4-424c-9813-186d144e6624")
options("tercen.stepId"     = "5ae79b70-5195-4578-8439-eaf21b9a250b")
#options("tercen.stepId"     = "7df2d0f2-63fc-4230-9fa8-53ee2ebaed8d")

### FUNCTION table

change.format <- function(table){
  #pop<-table[,1]
  #mark<-table[,2]
  
  out.mat<-matrix(, nrow = 1, ncol =0)
  
  for (rownb in c(1:nrow(table))){
    #print(table[rownb,])
    tbl.row<-table[rownb,]
    
    pop<-tbl.row[[1]]
    marker<-tbl.row[[2]]
    marker<-str_replace(marker,"\\+\\+","hi")
    
    list<-unlist(strsplit(marker, "(?<=[\\+|\\-]|lo|hi)", perl=TRUE))
    out.tmp<-rbind(list)
    out.tmp<-cbind(pop,out.tmp)
    #rownames(out.tmp)<- pop
    clean.list<-gsub('[\\+|\\-]|lo|hi', '', list)
    colnames(out.tmp)[-1]<- clean.list
    
    save.pop<-out.tmp[,1]
    
    out.tmp[grep(out.tmp,pattern = "\\+")]<-1
    out.tmp[grep(out.tmp,pattern = "\\-")]<--1
    out.tmp[grep(out.tmp,pattern = "lo")]<-0.5
    out.tmp[grep(out.tmp,pattern = "hi")]<-2
    
    out.tmp[,1]<-save.pop
    
    dat2 <- as.matrix(out.tmp,keep.rownames=FALSE)
    
    dat1 <- as.matrix(out.mat)
    #Assign to an object
    out.mat <- merge(dat1, dat2, all = TRUE)
    #out.mat
    #Replace NA's with zeros
    out.mat[is.na(out.mat)] <- 0
    
  }
  return( out.mat)
}





ctx <- tercenCtx()

### Extract the population table with the documentId
#doc.id<-ctx$select("js1.documentId")[[1]][1]

doc.id.tmp<-as_tibble(ctx$select())
doc.id<-doc.id.tmp[[grep("documentId" , colnames(doc.id.tmp))]][1]

table.pop<-ctx$client$tableSchemaService$select(doc.id)

tbl_pop<-as_tibble(table.pop)
tbl_pop <- as.matrix(tbl_pop)
tbl_pop<-change.format(tbl_pop)
Population = tbl_pop[1]
tbl_pop <- tbl_pop[,-1]
rownames(tbl_pop) <- Population[[1]]

#previous format
#tbl_pop<-as_tibble(table.pop)
#Population = tbl_pop[1]
#tbl_pop %<>% select(-colnames(tbl_pop)[1]) %>% as.matrix
#rownames(tbl_pop) = Population[[1]]


mem_matrix<-ctx %>% 
  select(.ci, .ri, .y)

channel_list<-ctx$rselect()
data_mem<-pivot_wider(mem_matrix,names_from = .ri, values_from = .y)
channel_list[[1]]<-str_replace(channel_list[[1]],"HLA-DR","HLADR")
colnames(data_mem)[-1]<-channel_list[[1]]
#colnames(data_mem)[-1]<-c("HLADR","pERK1","CD3","Perf","CD38","IFNg","CD4","CD8")


range <- function(x){(x-min(x))/(max(x)-min(x))}
data_mem[-1]<-range(data_mem[-1])



out.mat<-matrix(, nrow = 0, ncol = 2)
for (cluster.nb in c(1:length(data_mem[[".ci"]]))){
  label<-data_mem[[".ci"]][cluster.nb]
  population<-""
  for (cname in colnames(data_mem)[-1]){
  positive.threshold <- as.double(ctx$op.value("Positive Threshold"))
  low.threshold <- as.double(ctx$op.value("Low Threshold"))
  high.threshold <- as.double(ctx$op.value("High Threshold"))
  positive.threshold <- -2
  low.threshold <- -2
  high.threshold <- 10
 
  if (data_mem[cluster.nb,cname]< positive.threshold){
    population<-paste(population,cname,"-",sep="")
  }else{
    if (data_mem[cluster.nb,cname]> high.threshold){
      population<-paste(population,cname,"hi",sep="")
    } else if (data_mem[cluster.nb,cname]< low.threshold){
      population<-paste(population,cname,"lo",sep="")
    } else{
      population<-paste(population,cname,"+",sep="")
    }
  }
  }
  res<-cbind(label,population)
  out.mat<-rbind(out.mat,res)
}


###
find.match<- function(cluster_pop,tbl_pop){
  population.list<-c()
  
  for (i in c(1:length(rownames(tbl_pop)))){
    pop.name<-rownames(tbl_pop)[i]
    marker.list<-c()
    
    for (y in c(1:length((tbl_pop[i,])))){
      if (tbl_pop[i,y] == 1){
        marker<- paste(colnames(tbl_pop)[y],"+",sep="")
      } else if(tbl_pop[i,y] == 2){
        marker<- paste(colnames(tbl_pop)[y],"hi",sep="")
      } else if(tbl_pop[i,y] == -1){
        marker<- paste(colnames(tbl_pop)[y],"-",sep="")
      } else if(tbl_pop[i,y] == 0.5){
        marker<- paste(colnames(tbl_pop)[y],"lo",sep="")
      } else{
        marker<-""
      }
      marker.list<-append(marker.list,marker)
    }
    
    unmatch<-FALSE
    for(element in marker.list){
    match<-grepl(element, cluster_pop["population"],fixed = TRUE)
      if(!match){
        #print("unmatch")
        unmatch<-TRUE
        break
      }
    }
    
    if (!unmatch){
      population.list<-append(population.list,pop.name)
    }
  }
  return(population.list)
}

population_col <-rownames(tbl_pop)
output<-matrix(, nrow = 0, ncol = length(population_col)+1)
colnames(output)<-c(".ci",population_col)

for (row.nb in c(1:length(out.mat[,1]))){
  result<-find.match(out.mat[row.nb,],tbl_pop)
  .ci<-as.numeric(row.nb)
  for (ref.pop in population_col){
    if(ref.pop %in% result){
      .ci<-cbind(.ci,"TRUE")
    } else{
      .ci<-cbind(.ci,"FALSE")
    }
  }
  output<-rbind(output,.ci)
}

output2<-matrix(, nrow = 0, ncol = 2)
for (row.nb in c(1:length(out.mat[,1]))){
  result<-find.match(out.mat[row.nb,],tbl_pop)
  for (res.pop in result){
    new.row<-cbind(as.numeric(row.nb),res.pop)
    output2<-rbind(output2,new.row)
  }
  if(is.null(result)){
    new.row<-cbind(as.numeric(row.nb),"Unknown")
    output2<-rbind(output2,new.row)
  }
}
colnames(output2)<-c(".ci","population")

final.output<-merge(output, output2, by = ".ci")

final.output%>%
  as_tibble()%>% 
  mutate(.ci = as.integer(as.integer(.ci)-1)) %>%
  ctx$addNamespace() %>%
  ctx$save()

