#
#
#
library(caret)
library(Matrix)
source("BuildTestList.R")
source("PredictNextWord.R")

testWordPrediction <- function(inputDataFilenames, runQueueFilename) {
    #Load Run Queue
    runQueue <- read.csv(runQueueFilename, comment.char = "#", row.names=1)
    
    for(aRunNo in 1:nrow(runQueue)) {
        writeLines(c("",paste0("Building a list for test run ", aRunNo, " of ", nrow(runQueue))))
        if(!is.na(runQueue[aRunNo, "Accuracy"])) {
            writeLines("   Results already in runQueue file. Skipping")
            next
        }
        
        fileNoToLoad <- as.integer(runQueue[aRunNo, "filesToLoad"])
        if(fileNoToLoad < 1 | fileNoToLoad > 7) {
            fileNoToLoad <- 7
            runQueue[aRunNo, "filesToLoad"] <- 7
        }
        
        inputDataFilenamesToUse <- c()
        if(fileNoToLoad >= 4) {
            inputDataFilenamesToUse <- append(inputDataFilenamesToUse,
                                              inputDataFilenames[3])
            fileNoToLoad <- fileNoToLoad - 4
        }
        if(fileNoToLoad >= 2) {
            inputDataFilenamesToUse <- append(inputDataFilenamesToUse,
                                              inputDataFilenames[2])
            fileNoToLoad <- fileNoToLoad - 2
        }
        if(fileNoToLoad == 1) {
            inputDataFilenamesToUse <- append(inputDataFilenamesToUse,
                                              inputDataFilenames[1])
            fileNoToLoad <- fileNoToLoad - 1
        }
        if(fileNoToLoad != 0) {
            writeLines(c("We have a problem.",fileNoToLoad))
            next
        }
        
        aRunDataBaseFilename <- paste0("MarkovChains//markovChain",
                                       runQueue[aRunNo, "NoLinesEachFileOrFraction"],
                                       runQueue[aRunNo, "LocToReadLines"],
                                       "cumPer",
                                       as.integer(
                                           as.numeric(runQueue[aRunNo,
                                                               "cumPercent"])*100),
                                       "wFNo", runQueue[aRunNo, "filesToLoad"],
                                       "TSP",
                                       round(as.numeric(runQueue[aRunNo,
                                                                 "trainSkipPenalty"]),1))
        aRunDataMCSpFilename <- paste0(aRunDataBaseFilename, "SpMC.txt")
        predictorWordListFilename <- paste0(aRunDataBaseFilename, "SpORWL.csv")
        predictedWordListFilename <- paste0(aRunDataBaseFilename, "SpEDWL.csv")
        aRunDataTrainNosFilename <- paste0(aRunDataBaseFilename, "TrainNos.csv")        aRunTestListFilename <- paste0(aRunDataBaseFilename, "PSP",
                                       round(runQueue[aRunNo, "predictSkipPenalty"],1),
                                       "noPred", runQueue[aRunNo, "noWordsToPredict"],
                                       "testList.csv")
        
        if(all(file.exists(aRunDataMCSpFilename, aRunDataTrainNosFilename,
                           predictorWordListFilename,
                           predictedWordListFilename))) {
            #Load trained data and training line numbers from files
            mCWordSpMatrix <- readMM(aRunDataMCSpFilename)
            predictorWordList <- read.csv(predictorWordListFilename,
                                   comment.char="#", row.names=1)
            predictedWordList <- read.csv(predictedWordListFilename,
                                          comment.char="#", row.names=1)
            trainLineNos <- read.csv(aRunDataTrainNosFilename,
                                     comment.char="#", row.names=1)
        } else {
            writeLines(paste0("   All files for testing are not available for ",
                              aRunDataBaseFilename, "."))
            next
        }
        if(file.exists(aRunTestListFilename)) {
            writeLines(paste0("   Test list file exists. Reading file",
                              aRunTestListFilename))
            testList <- read.csv(aRunTestListFilename, comment.char = "#",
                                 row.names=1)
        } else {
            writeLines(paste0("   Test list file does not exists. Creating file", aRunTestListFilename))
            #Create test list from text data files
            testList <- data.frame(origLine = as.character(),
                                   #nMin4Word = as.character(),
                                   nMin3Word = as.character(),
                                   nMin2Word = as.character(),
                                   nMin1Word = as.character(),
                                   testWord  = as.character())
            noLinesToReadFromEach <- runQueue[aRunNo, "NoLinesEachFileOrFraction"]
            locationToReadLines <- runQueue[aRunNo, "LocToReadLines"]
            trainPercent <- runQueue[aRunNo, "trainPercent"]
            if(!(locationToReadLines %in% c("top", "random"))) {
                writeLines("   Invalid read lines location in queue. Skipping run.")
                next
            }
            for(anInputFilename in inputDataFilenamesToUse) {
                tempTestList <- buildTestList(anInputFilename,
                                              noLinesToReadFromEach=noLinesToReadFromEach,
                                              locationToReadLines=locationToReadLines,
                                              trainLineNos = trainLineNos$trainSampNos,
                                              testPercent = 1 - trainPercent)
                testList <- rbind(testList, tempTestList)
                #testlist format
                #(Orig. String, list of words to a point, n-3 word, n-2 word, n-1 word, n/test word)
            }
            #Convert testList to character variables as they are being coerced into factors
            testList$nMin4Word <- as.character(testList$nMin4Word)
            testList$nMin3Word <- as.character(testList$nMin3Word)
            testList$nMin2Word <- as.character(testList$nMin2Word)
            testList$nMin1Word <- as.character(testList$nMin1Word)
            testList$testWord  <- as.character(testList$testWord)
            testList$origLine  <- as.character(testList$origLine)
            
            #For newly created test lists, set 'prediction1' as NA
            testList$prediction1 <- NA
            
            #Save Test List to File with test but not results
            write.csv(testList, aRunTestListFilename)
        }
        
        #If no prediction already, do a prediction test on each line in
        #testList and judge results. Add results to testList
        writeLines(c("",paste0("Starting tests for list ", aRunNo, " of ", nrow(runQueue))))
        predictSkipPenalty <- runQueue[aRunNo, "predictSkipPenalty"]
        lineNo <- 0
        nRowTestList <- nrow(testList)
        #print(paste("nRowTestList:", nRowTestList))
        #return("FALSE")
        lineCountPrint <- max(as.integer(nRowTestList/5), 1)
        for(aTestNo in (1:nRowTestList)) {
            #writeLines(c(paste("In 1:nRowTestList loop. Current: ")))
            #print(testList[aTestNo,,drop=FALSE])
            #writeLines(c(paste(".end.")))
            lineNo <- lineNo + 1
            if(!is.na(testList[aTestNo, "prediction1"])) next
            if((lineNo %% lineCountPrint) == 0) {
                writeLines(paste("   Predicting line", lineNo, "of", nRowTestList))
            }
            startTime <- proc.time()
            #writeLines(c(paste("tWP 1:", testList[aTestNo, "nMin4Word"], testList[aTestNo, "nMin3Word"], testList[aTestNo, "nMin2Word"], testList[aTestNo, "nMin1Word"],
            #                   aTestNo, "of", nrow(testList))))
            if(is.na(testList[aTestNo, "nMin2Word"])) {
                #writeLines(c(paste("tWP 1.11:", testList[aTestNo, "nMin1Word"])))
                newWordList <- c(testList[aTestNo, "nMin1Word"])
                #writeLines(c(paste("tWP 1.12:", testList[aTestNo, "nMin1Word"])))
                #writeLines(c(paste("tWP 1.13: newWordList:", newWordList)))
            } else {
                if(is.na(testList[aTestNo, "nMin3Word"])) {
                    #writeLines(c(paste("tWP 1.21:", testList[aTestNo, "nMin2Word"], testList[aTestNo, "nMin1Word"])))
                    newWordList <- c(testList[aTestNo, "nMin2Word"],
                                     testList[aTestNo, "nMin1Word"])
                    #writeLines(c(paste("tWP 1.22:", testList[aTestNo, "nMin2Word"], testList[aTestNo, "nMin1Word"])))
                    #writeLines(c(paste("tWP 1.23: newWordList:", newWordList)))
                    } else {
                    if(is.na(testList[aTestNo, "nMin4Word"])) {
                        #writeLines(c(paste("tWP 1.31:", testList[aTestNo, "nMin3Word"], testList[aTestNo, "nMin2Word"], testList[aTestNo, "nMin1Word"])))
                        newWordList <- c(testList[aTestNo, "nMin3Word"],
                                         testList[aTestNo, "nMin2Word"],
                                         testList[aTestNo, "nMin1Word"])
                        #writeLines(c(paste("tWP 1.32:", testList[aTestNo, "nMin3Word"], testList[aTestNo, "nMin2Word"], testList[aTestNo, "nMin1Word"])))
                        #writeLines(c(paste("tWP 1.33: newWordList:", newWordList)))
                    } else {
                        newWordList <- c(testList[aTestNo, "nMin4Word"],
                                         testList[aTestNo, "nMin3Word"],
                                         testList[aTestNo, "nMin2Word"],
                                         testList[aTestNo, "nMin1Word"])
                        #writeLines(c(paste("tWP 1.42:", testList[aTestNo, "nMin4Word"], testList[aTestNo, "nMin3Word"], testList[aTestNo, "nMin2Word"], testList[aTestNo, "nMin1Word"])))
                        #print(testList)
                        #writeLines(c(paste("tWP 1.43: newWordList:", newWordList)))
                    }
                }
            }
            noWordsToReturn <- runQueue[aRunNo, "noWordsToPredict"]
            #writeLines("tWP 2: newWordList: ")
            #print(newWordList)
            tempListOfPredictions <- as.character(predictNextWord(newWordList = newWordList,
                                                                  mCWordSpMatrix = mCWordSpMatrix,
                                                                  wordListDF= wordListDF,
                                                                  noWordsToReturn=noWordsToReturn,
                                                                  skipPenalty=predictSkipPenalty))
            #writeLines("tWP 2.1: tempListOfPreidictions: ")
            #print(tempListOfPredictions)
            count <- 1
            correctFlag <- FALSE
            for(aPredict in tempListOfPredictions) {
                if(aPredict == FALSE) {    #No matches found
                    break
                }
                thisPredictName <- paste0("prediction", as.character(count))
                testList[aTestNo, thisPredictName] <- aPredict
                if(testList[aTestNo, thisPredictName] == testList[aTestNo, "testWord"]) {
                    correctFlag <- TRUE
                }
                count <- count + 1
            }
            if(!is.na(testList[aTestNo, "prediction1"])) {
                testList[aTestNo, "timeToPredict"] <- (proc.time() - startTime)[1]
            } else {
                testList[aTestNo, "timeToPredict"] <- NA
            }
            
            #print(c("prediction: ", testList[aTestNo, "prediction"], "actual: ", testList[aTestNo, "testWord"]))
            
            if(correctFlag) {
                testList[aTestNo, "Correct"] <- TRUE
            } else {
                testList[aTestNo, "Correct"] <- FALSE
            }
        }
        
        writeLines("  Finished predicting all lines in file. Writing testList and saving metrics")
        write.csv(testList, aRunTestListFilename)
        runQueue[aRunNo, "Accuracy"] <- round(sum(testList$Correct * 1) / length(testList$Correct),4)
        runQueue[aRunNo, "avgTimeToPredict"] <- round(mean(testList$timeToPredict, na.rm=TRUE),3)
        runQueue[aRunNo, "sdTimeToPredict"] <- round(sd(testList$timeToPredict, na.rm=TRUE),3)
        write.csv(runQueue, runQueueFilename)
    }
}