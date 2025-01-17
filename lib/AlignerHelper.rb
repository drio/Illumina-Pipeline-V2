#!/usr/bin/ruby

$:.unshift File.dirname(__FILE__)

require 'EmailHelper'
require 'EnvironmentInfo'
require 'yaml'

# Class to consume a SAM file generated by BWA and apply various fixups to
# produce the final BAM file and calculate alignment stats on it.
# Author: Nirav Shah niravs@bcm.edu:w
#
class AlignerHelper
  def initialize(samFileName, finalBAMName, fcBarcode, isFragment)
   
    # Maintain various filenames
    @samFile   = samFileName  # SAM file produced by BWA
    @finalBam  = finalBAMName # Final BAM

    # Intermediate BAM which is coordinate sorted but without marking duplicates
    @sortedBam = samFileName.gsub(/\.sam$/, "_sorted.bam")

    @fcBarcode     = fcBarcode.to_s # Flowcell barcode
    @isFragment    = isFragment     # true if fragment lane, false otherwise

    getEnvironmentConfigParams()
  end

  # Main worker method to produce a BAM
  def makeBAM()
    puts "Displaying execution environment"
    EnvironmentInfo.displayEnvironmentInformation($stdout, true)

    if @isFragment == false
       # For a paired-end BAM, fix the mate information and CIGAR
       cmd = fixMateInfoCustomCommand(@samFile, @sortedBam)
       runCommand(cmd, "MateInfoFixer")
    else
      # For a fragment BAM, run SortSAM and then fix CIGAR
      cmd = sortBamCommand(@samFile, @sortedBam)
      runCommand(cmd, "SortBam")

      # Now fix CIGAR
      cmd = fixCIGARCommand(@sortedBam)
      runCommand(cmd, "CigarFixer")
    end

    # Run mark duplicates command
    cmd = markDupCommand(@sortedBam, @finalBam)
    runCommand(cmd, "MarkDuplicates")

    # Calculate mapping and other stats
    cmd = mappingStatsCommand(@finalBam)
    runCommand(cmd, "BAMAnalyzer")
  end

  private

  # Obtain various parameter values to run Picard commands and to run custom
  # Java applications.
  def getEnvironmentConfigParams()
    # Directory hosting various custom-built jars
    @javaDir  = File.dirname(File.expand_path(File.dirname(__FILE__))) + "/java"

    # Read picard parameters from yaml config file
    yamlConfigFile = File.dirname(File.expand_path(File.dirname(__FILE__))) +
                     "/config/config_params.yml"
    configReader =  YAML.load_file(yamlConfigFile)
    
    # Parameters for picard commands
    @picardPath       = configReader["picard"]["path"]
    @picardValStr     = configReader["picard"]["stringency"]
    @picardTempDir    = configReader["picard"]["tempDir"]
    @maxRecordsInRam  = configReader["picard"]["maxRecordsInRAM"]
    @heapSize         = configReader["picard"]["maxHeapSize"]
  end

  # Command to sort a BAM
  def sortBamCommand(input, output)
    cmd = "java " + @heapSize + " -jar " + @picardPath + "/SortSam.jar I=" +
           input + " O=" + output + " SO=coordinate " + @picardTempDir +
           " " + @maxRecordsInRam.to_s + " " + @picardValStr +  
           " 1>sortbam.o 2>sortbam.e"
    return cmd
  end

  # Mark duplicates on a sorted BAM
  def markDupCommand(input, output)
    cmd = "java " + @heapSize + " -jar " + @picardPath + "/MarkDuplicates.jar " +
          " I=" + input +  " O=" + output + " " + @picardTempDir + " " +
          @maxRecordsInRam.to_s + " AS=true M=metrics.foo " +
          @picardValStr  + " 1>markDups.o 2>markDups.e"
    return cmd
  end

  # Correct the flag describing the strand of the mate
  # This function uses Picard's FixMateInformation.jar
  def fixMateInfoPicardCommand(input, output)
    cmd = "java " + @heapSize + " -jar " + @picardPath + "/FixMateInformation.jar " +
          "I=" + input + " O=" + output + " SO=coordinate " + @picardTempDir +
          " " + @maxRecordsInRam.to_s + " " + @picardValStr +
          " 1>fixMateInfo.o 2>fixMateInfo.e"
    return cmd
  end

  # Use custom tool to fix the flag describing strand of the mate. It will also
  # fix CIGAR for unmapped reads, i.e., include fixCIGARCmd
  def fixMateInfoCustomCommand(input, output)
    jarName = @javaDir + "/MateInfoFixer.jar"
    cmd = "java " + @heapSize + " -jar " + jarName + " I=" + input +
          " O=" + output + " FUR=true " +  @picardTempDir + " " +
          @maxRecordsInRam.to_s + " " + @picardValStr + " 1>mateInfoFixer.o " +
          "2>mateInfoFixer.e"
    return cmd
  end

  # Correct the unmapped reads. Reset CIGAR to * and mapping quality to zero.
  # This command overwrites the input file with the fixed file.
  def fixCIGARCommand(input)
    jarName = @javaDir + "/CIGARFixer.jar"
    cmd = "java " + @heapSize + " -jar " + jarName + " I=" + input +
          " 1>fixCIGAR.o 2>fixCIGAR.e"
    return cmd
  end

  # Method to build command to calculate mapping stats
  def mappingStatsCommand(input)
    puts "java dir"
    puts @javaDir
    jarName = @javaDir + "/BAMAnalyzer.jar"
    cmd = "java " + @heapSize + " -jar " + jarName + " I=" + input +
          " O=BWA_Map_Stats.txt X=BAMAnalysisInfo.xml " +
          "1>mappingStats.o 2>mappingStats.e" 
    return cmd
  end

  # Method to run the specified command
  def runCommand(cmd, cmdName)
    puts "Running command " + cmdName.to_s
    startTime = Time.now
    `#{cmd}`
    endTime   = Time.now
    returnValue = $?

    timeDiff = (endTime - startTime) / 3600
    puts "Execution time : " + timeDiff.to_s + " hours"

    if returnValue != 0
      handleError(cmdName)
    end
  end

   # Method to handle error. Current behavior, print the error stage and abort.
  def handleError(commandName)
    errorMessage = "Error while processing command : " + commandName.to_s +
                   " for flowcell : " + @fcBarcode.to_s + " Working Dir : " +
                   Dir.pwd.to_s + " Hostname : " +  EnvironmentInfo.getHostName() 

    obj          = EmailHelper.new()
    emailFrom    = "sol-pipe@bcm.edu"
    emailTo      = obj.getErrorRecepientEmailList()
    emailSubject = "Mapping error for lane barcode " + @fcBarcode.to_s 

    obj.sendEmail(emailFrom, emailTo, emailSubject, errorMessage)
    puts errorMessage.to_s
    exit -1
  end
end

param4 = ARGV[3]
if param4.eql?("false")
  isFragment = false
else
  isFragment = true
end

obj = AlignerHelper.new(ARGV[0], ARGV[1], ARGV[2], isFragment)
obj.makeBAM()
