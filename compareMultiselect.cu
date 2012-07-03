/* Based on compareAlgorithms.cu */

#include <cuda.h>
#include <curand.h>
#include <cuda_runtime_api.h>

#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <sys/time.h>

#include <algorithm>
//Include various thrust items that are used
#include <thrust/reduce.h>
#include <thrust/functional.h>
#include <thrust/device_ptr.h>
#include <thrust/scan.h>
#include <thrust/extrema.h>
#include <thrust/pair.h>

//various functions, include the functions
//that print numbers in binary.
#include "printFunctions.cu"

//the algorithms
#include "bucketMultiselect.cu"


#include "generateProblems.cu"
#include "multiselectTimingFunctions.cu"

#define NUMBEROFALGORITHMS 2
char* namesOfMultiselectTimingFunctions[NUMBEROFALGORITHMS] = {"Sort and choose multiselect", "Bucket multiselect"};


using namespace std;
template<typename T>
void compareMultiselectAlgorithms(uint size, uint * kVals, uint kCount, uint numTests, uint *algorithmsToTest, uint generateType, char* fileNamecsv) {
  T *h_vec, *h_vec_copy;
  float timeArray[NUMBEROFALGORITHMS][numTests];
  T * resultsArray[NUMBEROFALGORITHMS][numTests];
  float totalTimesPerAlgorithm[NUMBEROFALGORITHMS];
  uint winnerArray[numTests];
  uint timesWon[NUMBEROFALGORITHMS];
  uint i,j,m,x;
  int runOrder[NUMBEROFALGORITHMS];

  unsigned long long seed;
  results_t<T> *temp;
  ofstream fileCsv;
  timeval t1;
 
  typedef results_t<T>* (*ptrToTimingFunction)(T*, uint, uint *, uint);
  typedef void (*ptrToGeneratingFunction)(T*, uint, curandGenerator_t);

  //these are the functions that can be called
  ptrToTimingFunction arrayOfTimingFunctions[NUMBEROFALGORITHMS] = {&timeSortAndChooseMultiselect<T>,
                                                                    &timeBucketMultiselect<T>};
  
  ptrToGeneratingFunction *arrayOfGenerators;
  char** namesOfGeneratingFunctions;
  //this is the array of names of functions that generate problems of this type, ie float, double, or uint
  namesOfGeneratingFunctions = returnNamesOfGenerators<T>();
  arrayOfGenerators = (ptrToGeneratingFunction *) returnGenFunctions<T>();

  printf("Files will be written to %s\n", fileNamecsv);
  fileCsv.open(fileNamecsv, ios_base::app);
  
  //zero out the totals and times won
  bzero(totalTimesPerAlgorithm, NUMBEROFALGORITHMS * sizeof(uint));
  bzero(timesWon, NUMBEROFALGORITHMS * sizeof(uint));

  //allocate space for h_vec, and h_vec_copy
  h_vec = (T *) malloc(size * sizeof(T));
  h_vec_copy = (T *) malloc(size * sizeof(T));

  //create the random generator.
  curandGenerator_t generator;
  srand(unsigned(time(NULL)));

  printf("The distribution is: %s\n", namesOfGeneratingFunctions[generateType]);
  for(i = 0; i < numTests; i++) {
    // cudaDeviceReset();
    gettimeofday(&t1, NULL);
    seed = t1.tv_usec * t1.tv_sec;
    
    for(m = 0; m < NUMBEROFALGORITHMS;m++)
      runOrder[m] = m;
    
    std::random_shuffle(runOrder, runOrder + NUMBEROFALGORITHMS);
    fileCsv << size <<"," << kVals[kCount - 1] << "," << namesOfGeneratingFunctions[generateType] << "," << seed<< ",";
    curandCreateGenerator(&generator, CURAND_RNG_PSEUDO_DEFAULT);
    curandSetPseudoRandomGeneratorSeed(generator,seed);
    printf("Running test %u of %u for size: %u and numK: %u\n", i + 1, numTests,size,kCount);
    //generate the random vector using the specified distribution
    arrayOfGenerators[generateType](h_vec, size, generator);

    //copy the vector to h_vec_copy, which will be used to restore it later
    memcpy(h_vec_copy, h_vec, size * sizeof(T));

    winnerArray[i] = 0;
    float currentWinningTime = INFINITY;
    //run the various timing functions
    for(x = 0; x < NUMBEROFALGORITHMS; x++){
      j = runOrder[x];
      if(algorithmsToTest[j]){

        //run timing function j
        printf("TESTING: %u\n", j);
        temp = arrayOfTimingFunctions[j](h_vec_copy, size, kVals, kCount);

        //record the time result
        timeArray[j][i] = temp->time;
        //record the value returned
        resultsArray[j][i] = temp->vals;
        //update the current "winner" if necessary
        if(timeArray[j][i] < currentWinningTime){
          currentWinningTime = temp->time;
          winnerArray[i] = j;
        }

        //perform clean up 
        free(temp);
        memcpy(h_vec_copy, h_vec, size * sizeof(T));
      }
    }

    curandDestroyGenerator(generator);
    for(x = 0; x < NUMBEROFALGORITHMS; x++)
      if(algorithmsToTest[x])
        fileCsv << namesOfMultiselectTimingFunctions[x] << "," << resultsArray[x][i] << "," << timeArray[x][i] << ",";

    uint flag = 0;
    for(m = 1; m < NUMBEROFALGORITHMS;m++)
      if(algorithmsToTest[m])
        for (j = 0; j < kCount; j++) {
          T tempResult = resultsArray[0][i][j];
          if(resultsArray[m][i][j] != tempResult)
            flag++;
        }

    fileCsv << flag << "\n";
  }
  
  //calculate the total time each algorithm took
  for(i = 0; i < numTests; i++)
    for(j = 0; j < NUMBEROFALGORITHMS;j++)
      if(algorithmsToTest[j])
        totalTimesPerAlgorithm[j] += timeArray[j][i];


  //count the number of times each algorithm won. 
  for(i = 0; i < numTests;i++)
    timesWon[winnerArray[i]]++;

  printf("\n\n");

  //print out the average times
  for(i = 0; i < NUMBEROFALGORITHMS; i++)
    if(algorithmsToTest[i])
      printf("%-20s averaged: %f ms\n", namesOfMultiselectTimingFunctions[i], totalTimesPerAlgorithm[i] / numTests);

  for(i = 0; i < NUMBEROFALGORITHMS; i++)
    if(algorithmsToTest[i])
      printf("%s won %u times\n", namesOfMultiselectTimingFunctions[i], timesWon[i]);

  for(i = 0; i < numTests; i++)
    for(j = 1; j < NUMBEROFALGORITHMS; j++)
      for (m = 0; m < kCount; m++)
        if(algorithmsToTest[j])
          if(resultsArray[j][i][m] != resultsArray[0][i][m]) {
            std::cout <<namesOfMultiselectTimingFunctions[j] <<" did not return the correct answer on test" << i + 1 << " it got "<< resultsArray[j][i];
            std::cout << "instead of " << resultsArray[0][i][m] << "\n" ;
            std::cout << "RESULT:\t";
            PrintFunctions::printBinary(resultsArray[j][i][m]);
            std::cout << "Right:\t";
            PrintFunctions::printBinary(resultsArray[0][i][m]);
          }

  for(i = 0; i < numTests; i++) 
    for(m = 0; m < NUMBEROFALGORITHMS; m++) 
      if(algorithmsToTest[m])
        free(resultsArray[m][i]);


  //free h_vec and h_vec_copy
  free(h_vec);
  free(h_vec_copy);
  //close the file
  fileCsv.close();
}


template<typename T>
void runTests(uint generateType, char* fileName,uint startPower, uint stopPower, uint timesToTestEachK = 100){
  uint algorithmsToRun[NUMBEROFALGORITHMS]= {1,0};
  uint size;
  uint i;
  uint arrayOfKs[25];
  for(size = (1 << startPower); size <= (1 << stopPower); size *= 2){
    //calculate k values
    arrayOfKs[0]= 2;
    arrayOfKs[1] = .01 * size;
    arrayOfKs[2] = .025 * size;
    for(i = 1; i <= 19; i++)
      arrayOfKs[i + 2] = (.05 * i) * size;
    
    arrayOfKs[22] = .975 * size;
    arrayOfKs[23] = .99 * size;
    arrayOfKs[24] = size-1;

    for(i = 0; i <25; i++){
      //  cudaDeviceReset();
      cudaThreadExit();
      printf("NOW STARTING A NEW K\n\n"); 
      compareMultiselectAlgorithms<T>(size, arrayOfKs, i + 1, timesToTestEachK, algorithmsToRun, generateType, fileName);
    }
  }
}


int main(int argc, char *argv[]) {
  char *fileName;

  uint testCount;
  fileName = (char*) malloc(60 * sizeof(char));
  printf("Please enter filename now: ");
  scanf("%s%",fileName);

  uint type,distributionType,startPower,stopPower;
  
  printf("Please enter the type of value you want to test:\n1-float\n2-double\n3-uint\n");
  scanf("%u", &type);
  printf("Please enter Distribution type: ");
  scanf("%u", &distributionType);
  printf("Please enter  number of tests to run per K: ");
  scanf("%u", &testCount);
  printf("Please enter Start power: ");
  scanf("%u", &startPower);
  printf("Please enter Stop power: ");
  scanf("%u", &stopPower); 

  switch(type){
  case 1:
    runTests<float>(distributionType,fileName,startPower,stopPower,testCount);
    break;
  case 2:
    runTests<double>(distributionType,fileName,startPower,stopPower,testCount);
    break;
  case 3:
    runTests<uint>(distributionType,fileName,startPower,stopPower,testCount);
    break;
  default:
    printf("You entered and invalid option, now exiting\n");
    break;
  }

  free (fileName);
  return 0;
}