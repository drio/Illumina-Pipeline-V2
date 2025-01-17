#!/usr/bin/ruby

$:.unshift File.join(File.dirname(__FILE__), ".", "..", "lib")

require 'Scheduler'
require 'BWAParams'

#Commands to run after sequence generation is complete.
#Author: Nirav Shah niravs@bcm.edu

fcBarcode   = nil
inputParams = BWAParams.new()
inputParams.loadFromFile()
fcBarcode   = inputParams.getFCBarcode()

# Upload the sequence generation results (phasing, prephasing, raw clusters,
# percent purity filtered cluster and yield to LIMS.
uploadCmd = "ruby " + File.dirname(File.expand_path(__FILE__)) +
            "/ResultUploader.rb SEQUENCE_FINISHED"
output    = `#{uploadCmd}`
puts output

# Command to start sequence analysis
seqAnalyzerCmd = "ruby " + File.expand_path(File.dirname(__FILE__)) + "/SequenceAnalyzerWrapper.rb"
sch1 = Scheduler.new(fcBarcode + "_SequenceAnalysis", seqAnalyzerCmd)
sch1.setMemory(8000)
sch1.setNodeCores(1)
sch1.setPriority("normal")
sch1.runCommand()
uniqJobName = sch1.getJobName()

# Command to start the alignment
alignerCmd = "ruby " + File.dirname(File.expand_path(File.dirname(__FILE__))) +
             "/bin/Aligner.rb"

output = `#{alignerCmd}`
puts output
