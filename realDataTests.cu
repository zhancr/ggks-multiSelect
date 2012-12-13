#include <cuda.h>
#include <curand.h>
#include <cuda_runtime_api.h>

#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <sys/time.h>

#include "compareMultiselect.cu"
//#include "bucketMultiselect.cu"

#define BUF 256

int main(int argc, char** argv) {

  if(argc<2) {
    printf("Give a data file name\n");
    return 0;
  }

  char * filename = (char *)argv[1];
  //printf("%s\n",filename);
   
  FILE *file = fopen(filename, "r");
  if(file == NULL) {
    perror("fopen failed\n");
    return 0;
  }

  FILE *io;
  char sizeData[20];
  int size;
  char numsCall[BUF]= "wc -l < ";
  io = popen(strcat(numsCall, filename),"r"); 
  fgets(sizeData, 20, io);
  sscanf(sizeData, "%d", &size);
  pclose(io);

  printf("size %d\n", size);

  float * data= (float *) malloc(size*sizeof(float));
  char line[BUF];
  char *ptr;
  int count = 0;

  while (fgets(line, BUF, file) != NULL) {
    ptr =strtok(line, ",");
    ptr =strtok(NULL, ",");
    sscanf(ptr, "%f", &data[count]);
    count++;
  }
  printf("Reading done \n");

  /*
  float * d_data;
  cudaMalloc (&d_data, size*sizeof(float));
  cudaMemcpy (d_data, data, size*sizeof(float), cudaMemcpyHostToDevice);
  */
  /********************************************************************
  /************** READING DATA COMPLETED **************************
  /******************************************************************/
  char csvname[2*BUF];
  char *hostName;

  hostName = (char*) malloc(20 * sizeof(char));
  gethostname(hostName, 20);

  time_t rawtime;
  struct tm * timeinfo;
  time ( &rawtime );
  timeinfo = localtime ( &rawtime );
  char * humanTime = asctime(timeinfo);
  humanTime[strlen(humanTime)-1] = '\0';
  uint kDistribution,startK,stopK,jumpK,testCount;

  printf("Please enter K distribution type: ");
  printKDistributionOptions();
  scanf("%u", &kDistribution);
  printf("Please enter Start number of K values: ");
  scanf("%u", &startK);
  printf("Please enter number of K values to jump by: ");
  scanf("%u", &jumpK);
  printf("Please enter Stop number of K values: ");
  scanf("%u", &stopK);
  printf("Please enter number of tests to run per K: ");
  scanf("%u", &testCount);

  snprintf(csvname, 128, "%s comparison k-dist:%s (%d:%d:%d) %d-tests on %s at %s", filename, getKDistributionOptions(kDistribution), startK, jumpK, stopK, testCount, hostName, humanTime);

  uint algorithmsToRun[3]= {1, 1, 0};
  uint arrayOfKs[stopK+1];
  unsigned long long seed;
  timeval t1;
  gettimeofday(&t1, NULL);
  seed = t1.tv_usec * t1.tv_sec;
  curandGenerator_t generator;
  srand(unsigned(time(NULL)));
  curandCreateGenerator(&generator, CURAND_RNG_PSEUDO_DEFAULT);
  curandSetPseudoRandomGeneratorSeed(generator,seed);

  arrayOfKDistributionGenerators[kDistribution](arrayOfKs, stopK, size, generator);

  curandDestroyGenerator(generator);

  for(int i = startK; i <= stopK; i+=jumpK) {
    cudaDeviceReset();
    cudaThreadExit();
    printf("NOW ADDING ANOTHER K\n\n");
    CompareMultiselect::compareMultiselectAlgorithms<float>(size, arrayOfKs, i, testCount, algorithmsToRun, 0, kDistribution, csvname, data);
  }

  //cudaFree(d_data);
  fclose(file);
  free(data);
}
