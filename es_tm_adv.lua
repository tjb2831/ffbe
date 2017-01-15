-- More advanced script to farm Earth Shrine - Entrance.
-- This script attempts to do intelligent recovery in the event of failure,
-- such as a button not appearing due to lag
--
-- Assumptions:
--    1) The script is started on the Earth Shrine stage select screen
--    2) The TM team is the default team
--    3) All friend units are filtered out by the current friend filter
--    4) The TM team can auto through the ES entrance units
--    5) The Ankulua start/stop button is on the top edge of the screen (no lower than 200 px in y;
--       x dim doesn't matter)
--    6) (Toggleable in source) The user wants to use lapis refills
--
-- Note:
--    Steal scripting has been removed

-- ======= Settings ===========
-- Use 1536x2048 as comparison dimensions
HEIGHT = 2048
WIDTH = 1536
Settings:setCompareDimension(true, WIDTH)  -- True flag denotes width
Settings:setCompareDimension(false, HEIGHT) -- False flag denotes height

-- Script (and images) use 1536x2048 as screen dims
Settings:setScriptDimension(true, WIDTH)
Settings:setScriptDimension(false, HEIGHT)

-- Settings used by app logic
transition_jitter = true   -- Add some random delta to screen transitions
use_lapis = true           -- Refill energy with lapis when we run out
do_logging = false         -- Log click events to file
highlight_clicks = false   -- Highlight the click location for a few seconds (adds notable delay)
highlight_duration = 1     -- Number of seconds to highlight clicks
logfile = nil              -- handle to log
numFailedMatches = 0       -- Number of consecutive failed matches

-- Global state variables (named here for verbosity)
stageIdx = 1               -- Index of current stage
isRelaunching = false      -- App is currently relaunching
isRecovering = false       -- Recovering due to inconsistency between current stageIdx and what's on screen

-- Normal stages.
-- MUST be in the correct sequential order, as if nothing went wrong!
STAGE_SELECT_SCREEN = 1
MISSION_SCREEN = 2
COMPANION_SELECT_SCREEN = 3
TEAM_SELECT_SCREEN = 4
BATTLE_SCREEN = 5
RESULTS_SCREEN_1 = 6
RESULTS_SCREEN_2 = 7
RESULTS_SCREEN_3 = 8

-- Special stages that appear sporadically or under special circumstances
ENERGY_REFILL_SCREEN = 1000
DISCONNECTED_SCREEN = 1001
DAILY_STORY_COMP_SCREEN = 1002
APP_CRASHED = 1003


-- String descriptions of normal stages (for end-of-script messages)
stages = {
   [STAGE_SELECT_SCREEN] = "Stage Select",       -- Select ES entrance stage
   [MISSION_SCREEN] = "Mission Screen",     -- Select "Next" on missions screen
   [COMPANION_SELECT_SCREEN] = "Companion Screen",   -- Select "Depart without companions" on companion select screen
   [TEAM_SELECT_SCREEN] = "Team Screen",        -- Select "Depart" on team selection screen
   [BATTLE_SCREEN] = "Battle Screen",      -- Select "Auto" on battle screen
   [RESULTS_SCREEN_1] = "Results Screen 1",   -- Select "Next" on first results screen (Total Exp, gil, rank exp)
   [RESULTS_SCREEN_2] = "Results Screen 2",   -- Click anywhere on second results screen (Unit growth)
   [RESULTS_SCREEN_3] = "Results Screen 3",   -- Select "Next" on third results screen (Materials)
}

-- Stages are not added at runtime, so cache the number of stages
numStages = 0
for _ in pairs(stages)
do
   numStages = numStages + 1
end

-- Add special stages to stages mapping.
-- Kind of hacky, but it works. Alternatively, use a different table.
--
-- MUST BE AFTER THE NUM STAGES COUNTING LOOP
stages[ENERGY_REFILL_SCREEN] = "Energy Refill Prompt"
stages[DISCONNECTED_SCREEN] = "Network Disconnected Prompt"
stages[APP_CRASHED] = "FFBE Application Crashed"

-- Constant regions used to limit search areas (speedup search)
NO_HEADER = Region( 0, 250, WIDTH, HEIGHT - 250 )
TOP_HALF = Region( 0, 0, WIDTH, HEIGHT / 2 )
MIDDLE_HALF = Region( 0, HEIGHT / 4, WIDTH, HEIGHT / 2 )
BOTTOM_HALF = Region( 0, HEIGHT / 2, WIDTH, HEIGHT / 2 )
BOTTOM_QUARTER = Region( 0, 3 * HEIGHT / 4, WIDTH, HEIGHT / 4 )

-- ========== Show dialog for user preferences =========
function getUserPrefs()
   dialogInit()

   -- Add random lag between button clicks (timing jitter)
   addCheckBox( "transition_jitter", "Random button click delay", true )
   newRow()

   -- Use lapis when out of energy
   addCheckBox( "use_lapis", "Use lapis to refill energy", true )
   newRow()

   -- Highlight click locations
   addCheckBox( "highlight_clicks", "Highlight click locations (delays script)", false )
   newRow()
   addTextView( "Click highlight duration (seconds): " )
   addEditNumber( "highligh_duration", 2 )
   newRow()

   -- Log clicks
   addCheckBox( "do_logging", "Log click locations", false )
   newRow()
   addTextView( "Logfile name: " )
   addEditText( "logfile", "ffbe_adv_log.txt" )
   
   -- Show the dialog
   dialogShow( "Earth Shrine Farm Settings" )
   
end

-- ========== Log Message ==========
function log( severity, msg )
   if do_logging
   then
      local dateStr = os.date( "%H:%M:%S" )
      io.write( string.format( "%s -- %s: %s\n", dateStr, severity, msg ) )
      io.flush()
   end
end

-- ========== Initialization ========
function init()

   -- Get user settings
   getUserPrefs()

   -- Seed the PRNG 
   math.randomseed( os.time() )

   -- Open log file
   if do_logging
   then
      logfile = io.open( "/sdcard/Ankulua/ffbe/" .. logfile, "a" )
      if logfile
      then
         io.output( logfile )
         io.write( os.date( "\n -- Starting script on %d %b %Y at %H:%M:%S\n" ) )

         io.write( string.format(
                     "-- Settings:\n" ..
                     "\tClick time jitter = %s\n" ..
                     "\tRefill energy with lapis = %s\n" ..
                     "\tHighlight clicks = %s\n" ..
                     "\tHighlight duration = %.02f\n" ..
                     "-- End Settings\n",
                     ( transition_jitter and "true" or "false" ),
                     ( use_lapis and "true" or "false" ),
                     ( highlight_clicks and "true" or "false" ),
                     ( highlight_clicks and highlight_duration or "0.0" )
                     )
                  )

      else
         do_logging = false
      end
   end

   -- Make highlights filled yellow and semi-translucent
   if highlight_clicks
   then
      setHighlightStyle( 0x8fffff00, true )
   end
end

-- ============ Click a random area in given region of interest =============
function doClick( roi )
   -- Calculate random click location inside ROI
   local x = roi:getX() + math.random( roi:getW() )
   local y = roi:getY() + math.random( roi:getH() )
   
   -- Highlight the general area, if enabled
   if highlight_clicks
   then
      local roi_hl = Region( x - 25, y - 25, 50, 50 )
      roi_hl:highlight( highlight_duration )
   end

   -- Add random time delay (up to 1 second), if enabled
   if transition_jitter
   then
      wait( math.random() )
   end

   -- Click location on screen
   click( Location( x, y ) )
end

-- ============ Determine current stage based on what's on screen ===========
function determineStage()
   local checked = {}
   local nextStageIdx = 1
   if stageIdx ~= nil
   then
      nextStageIdx = stageIdx + 1
      if nextStageIdx > numStages then nextStageIdx = 1 end
   end

   -- Check that this stage is the expected next first (most likely scenario).
   -- If not, then check if we haven't transitioned from the last stage
   if matchStage( nextStageIdx, true )
   then
      return nextStageIdx
   elseif matchStage( stageIdx )
   then
      return stageIdx
   end

   -- Didn't find what was expected in normal flow. Check for special stages before
   -- searching (transitioning to recovery mode)
   
   -- Network disconnection
   if matchStage( DISCONNECTED_SCREEN )
   then
      handleReconnect()
      return determineStage()
   end

   -- Lapis Refill (only appears on stage 0 -> 1 transition)
   if stageIdx == 0 and matchStage( ENERGY_REFILL_SCREEN )
   then
      handleRefillPrompt()
      if use_lapis
      then
         return MISSION_SCREEN
      else
         log( "INFO", "Out of energy. Stopping script" )
         scriptExit( "Out of energy. Stopping script" )
      end
   elseif matchStage( DAILY_STORY_COMP_SCREEN )
   then
      handleDailyQuestsDialog()
      return STAGE_SELECT_SCREEN
   elseif matchStage( APP_CRASHED )
   then
      -- FFBE crashed. Relaunch it and figure out where we are
      relaunchFFBE()
      return determineStage()
   end

   -- No idea where we are. See if we can match the snapshot to a known screen
   for idx, _ in pairs( stages )
   do
      if matchStage( idx ) then return idx end
   end

   -- Couldn't match anything
   numFailedMatches = numFailedMatches + 1
   if numFailedMatches == 3
   then
      log( "ERR", "Failed to determine stage on last stage = " .. stages[stageIdx] )
      scriptExit( "Failed to determine stage on last stage = " .. stages[stageIdx] )
   end

   -- Don't know what stage we are on and we haven't hit 3 failed in a row.
   -- Try again.
   return determineStage()
end

-- ============ Check for the given stage (by index) =============
function matchStage( stageIdx, newSnap )
   usePreviousSnap( not newSnap )

   -- Massive wannabe switch statement for known stage indices
   if stageIdx == STAGE_SELECT_SCREEN
   then
      return BOTTOM_HALF:exists( "es_entrance.png" )
   elseif stageIdx == MISSION_SCREEN
   then
      return BOTTOM_QUARTER:exists( "next.png" )
   elseif stageIdx == COMPANION_SELECT_SCREEN
   then
      return TOP_HALF:exists( "depart_no_comp.png" )
   elseif stageIdx == TEAM_SELECT_SCREEN
   then
      return BOTTOM_QUARTER:exists( "depart.png" )
   elseif stageIdx == BATTLE_SCREEN
   then
      return BOTTOM_QUARTER:exists( "auto.png" )
   elseif stageIdx == RESULTS_SCREEN_1
   then
      return BOTTOM_QUARTER:exists( "next.png" )
   elseif stageIdx == RESULTS_SCREEN_2
   then
      return TOP_HALF:exists( "results.png" ) and not BOTTOM_HALF:exists( "next.png" )
   elseif stageIdx == RESULTS_SCREEN_3
   then
      return BOTTOM_QUARTER:exists( "next.png" )
   elseif stageIdx == ENERGY_REFILL_SCREEN
   then
      return MIDDLE_HALF:exists( "refill_prompt.png" )
   elseif stageIdx == DISCONNECTED_SCREEN
   then
      return MIDDLE_HALF:exists( "connection_error.png" )
   elseif stageIdx == DAILY_STORY_COMP_SCREEN
   then
      return MIDDLE_HALF:exists( "story_missions.png" )
   elseif stageIdx == APP_CRASHED
   then
      -- Assuming FFBE icon is on bottom half of home screen
      return BOTTOM_HALF:exists( "ffbe_icon_text.png" )
   end

   -- Invalid stage index
   log( "ERR", string.format( "Invalid stage index (%d)", stageIdx ) )
   return nil
end

-- ============ Handle Normal Stage =========
function handleStage( stageIdx )
   if stageIdx == STAGE_SELECT_SCREEN
   then
      doClick( BOTTOM_HALF:getLastMatch() )
      wait( 2 )
   elseif stageIdx == MISSION_SCREEN
   then
      doClick( BOTTOM_QUARTER:getLastMatch() )
      wait( 4 )
   elseif stageIdx == COMPANION_SELECT_SCREEN
   then
      doClick( TOP_HALF:getLastMatch() )
      wait( 2 )
   elseif stageIdx == TEAM_SELECT_SCREEN
   then
      doClick( BOTTOM_QUARTER:getLastMatch() )
      wait( 7 )
   elseif stageIdx == BATTLE_SCREEN
   then
      doClick( BOTTOM_QUARTER:getLastMatch() )
      wait( 10 )
      doClick( MIDDLE_HALF )
      wait( 10 )
   elseif stageIdx == RESULTS_SCREEN_1
   then
      doClick( BOTTOM_QUARTER:getLastMatch() )
      wait( 3 )
   elseif stageIdx == RESULTS_SCREEN_2
   then
      doClick( MIDDLE_HALF )     -- Click anywhere, no button to hit
      wait( 3 )
   elseif stageIdx == RESULTS_SCREEN_3
   then
      doClick( BOTTOM_QUARTER:getLastMatch() )
      wait( 1 )
   end
end

-- ============ Generic Dialog Handler =========
function handleDialog( clickPattern, matchPattern )
   local clicked = false
   while not clicked
   do
      local prompt = MIDDLE_HALF:getLastMatch()
      local roi = prompt:exists( clickPattern )
      if roi == nil
      then
         -- expected button wasn't in the last match. Try again with a new snapshot
         log( "ERR", "Unable to find " .. clickPattern .. " in dialog. " ..
              "Trying again with new snapshot" )
         
         usePreviousSnap( false )
         MIDDLE_HALF:exists( matchPattern )
      else
         doClick( roi )
         clicked = true
      end
   end
end

-- ============ Handle Network Disconnect Dialog ===========
function handleReconnect()
   handleDialog( "ok.png", "connection_error.png" )
   wait( 2 )
   log( "INFO", "Dismissed network disconnection dialog" )
end

-- ============ Handle Energy Refill Dialog ========
function handleRefillPrompt()
   if not use_lapis
   then
      keyevent( 4 )     -- Hit back button to dismiss dialog
   else
      handleDialog( "refill_yes.png", "refill_prompt.png" )
      wait( 2 )
   end
   
   log( "INFO", "Handled energy refill dialog" )
end

-- ============ Handle Daily Story Quests Complete Dialog =========
function handleDailyQuestsDialog()
   handleDialog( "close.png", "story_missions.png" )
   wait( 2 )
   log( "INFO", "Dismissed daily story mission dialog" )
end

-- ============ Relaunch app after crash =============
function relaunchFFBE()
   -- First, click the icon on home screen (no need to randomize location)
   click( BOTTOM_HALF:getLastMatch() )

   -- Wait for FFBE boot up sequence (splash screens)
   wait( 20 )

   -- Handle network failure
   local pastNetworkPrompt = false
   while not pastNetworkPrompt
   do
      if matchStage( DISCONNECTED_SCREEN, true )
      then
         handleReconnect()
         wait( 5 )
      else
         pastNetworkPrompt = true
      end
   end

   -- Click anywhere in middle half of screen. Avoid top and bottom
   -- of screen since they have some extra buttons we want to avoid
   doClick( MIDDLE_HALF )

   -- Wait for client to fully connect to server
   wait( 30 )
end

-- ============ Main Program ============

-- Initialize with user settings
init()

-- Main Processing Loop
while true
do

   numFailedMatches = 0
   
   -- Determine what stage we're in
   stageIdx = determineStage()

   -- Handle the current stage
   handleStage( stageIdx )

end
