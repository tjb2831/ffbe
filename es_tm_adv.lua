-- More advanced script to farm Earth Shrine - Entrance.
-- This script attempts to do intelligent recovery in the event of failure,
-- such as a button not appearing due to lag or FFBE crashing
--
-- Assumptions:
--    1) The script is started on the Earth Shrine stage select screen
--    2) The TM team is the default team
--    3) All friend units are filtered out by the current friend filter
--    4) The TM team can auto through the ES entrance units
--    5) Units are in the first and second slot (left column of battle screen,
--       top and middle position in 2x3 grid of units)
--    6) The Ankulua start/stop button is on the top edge of the screen (no lower than 200 px in y;
--       x dim doesn't matter)
--
-- Note:
--    Steal scripting has been removed

-- ======= Settings ===========

-- Settings used by app logic
transition_jitter = true   -- Add some random delta to screen transitions
use_lapis = true           -- Refill energy with lapis when we run out
do_logging = false         -- Log click events to file
highlight_clicks = false   -- Highlight the click location for a few seconds (adds notable delay)
highlight_duration = 1     -- Number of seconds to highlight clicks
use_pc_patterns = true 	   -- Hack: True to use pattern images captured from tablet, otherwise images are taken from PC screenshots
logfile = nil              -- handle to log
numFailedMatches = 0       -- Number of consecutive failed matches
numExceptions = 0          -- Number of consecutive exceptions (usually socket timeout between script and Ankulua daemon)
EXCEPTION_THRESHOLD = 25   -- Number of consecutive exceptions before leaving the script

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
LAPIS_CONFIRM_SCREEN = 1004      -- New for FFBE v2.0
SPLASH_SCREEN = 1005
RESUME_MISSION = 1006            -- Added sometime after v2.0 update, appears when resuming after crash
DISCONNECTED_SCREEN_ALT = 1007   -- Added sometime after the v2.3.1 update. Network disconnect prompt with less text
ADDL_DATA_DOWNLAD = 1008         -- Added in 3.4.1 update. Now prompts if there is data to download (happens on startup after crash)

-- String descriptions of normal stages (for end-of-script messages)
stages = {
   [STAGE_SELECT_SCREEN] = "Stage Select",            -- Select ES entrance stage
   [MISSION_SCREEN] = "Mission Screen",               -- Select "Next" on missions screen
   [COMPANION_SELECT_SCREEN] = "Companion Screen",    -- Select "Depart without companions" on companion select screen
   [TEAM_SELECT_SCREEN] = "Team Screen",              -- Select "Depart" on team selection screen
   [BATTLE_SCREEN] = "Battle Screen",                 -- Select "Auto" on battle screen
   [RESULTS_SCREEN_1] = "Results Screen 1",           -- Select "Next" on first results screen (Total Exp, gil, rank exp)
   [RESULTS_SCREEN_2] = "Results Screen 2",           -- Click anywhere on second results screen (Unit growth)
   [RESULTS_SCREEN_3] = "Results Screen 3",           -- Select "Next" on third results screen (Materials)
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
stages[LAPIS_CONFIRM_SCREEN] = "Energy Refill Lapis Usage Confirm Screen"
stages[DISCONNECTED_SCREEN] = "Network Disconnected Prompt"
stages[DISCONNECTED_SCREEN_ALT] = "Network Disconnected Prompt (Alt)"
stages[APP_CRASHED] = "FFBE Application Crashed"
stages[DAILY_STORY_COMP_SCREEN] = "Daily Story Missions Complete Prompt"
stages[SPLASH_SCREEN] = "Application Splash Screen"
stages[RESUME_MISSION] = "Resume Previous Mission Prompt"
stages[ADDL_DATA_DOWNLAD] = "Additional Data Download Prompt"

-- ============ Create constant regions of interest used to limit search areas (speedup search) =============
function createRegions( width, height )
   NO_HEADER = Region( 0, 250, width, height - 250 )
   TOP_HALF = Region( 0, 0, width, height / 2 )
   MIDDLE_HALF = Region( 0, height / 4, width, height / 2 )
   BOTTOM_HALF = Region( 0, height / 2, width, height / 2 )
   BOTTOM_QUARTER = Region( 0, 3 * height / 4, width, height / 4 )
end

-- ========== Show dialog for user preferences =========
function getUserPrefs()
   dialogInit()

   -- Add random lag between button clicks (timing jitter)
   addCheckBox( "transition_jitter", "Random button click delay", true )
   newRow()

   -- Use lapis when out of energy
   addCheckBox( "use_lapis", "Use lapis to refill energy", true )
   newRow()
   
   -- Use PC images
   addCheckBox( "use_pc_patterns", "Use images captured on PC", true )
   newRow()

   -- Highlight click locations
   addCheckBox( "highlight_clicks", "Highlight click locations (delays script)", false )
   newRow()
   addTextView( "Click highlight duration (seconds): " )
   addEditNumber( "highligh_duration", 2.0 )
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
                     "\tUse PC images = %s\n" ..
                     "\tHighlight clicks = %s\n" ..
                     "\tHighlight duration = %.02f\n" ..
                     "-- End Settings\n",
                     ( transition_jitter and "true" or "false" ),
                     ( use_lapis and "true" or "false" ),
                     ( use_pc_patterns and "true" or "false" ),
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
   
   -- Set where images for pattern recognition live
   local width = 0
   local height = 0
   if use_pc_patterns
   then
      setImagePath( scriptPath() .. "/image/pc/" )
      width = 1080
      height = 1920
	  
      UNIT_1_REGION = Region( 40, 1215, 480, 145 )
      UNIT_2_REGION = Region( 40, 1420, 480, 145 )
   else
      setImagePath( scriptPath() .. "/image/tablet/" )
      width = 1536
      height = 2048
	  
      UNIT_1_REGION = Region( 40, 1170, 690, 180 )
      UNIT_2_REGION = Region( 40, 1410, 690, 180 )
   end
   
   Settings:setCompareDimension( true, width )
   Settings:setCompareDimension( false, height )
   Settings:setScriptDimension( true, width )
   Settings:setScriptDimension( false, height )
   createRegions( width, height )
   
   -- Some image introspection
   Settings:snapSet( "OutputCaptureImg", true )
   Settings:snapSet( "OutputCropImg", true )
   Settings:snapSet( "OutputResizeImg", true )
   Settings:snapSet( "OutputRegImg", true )
end

-- ============ Click a random area in given region of interest =============
function doClick( roi, bypassJitter )
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
   if transition_jitter and not bypassJitter
   then
      wait( math.random() )
   end

   log( "INFO", string.format( "Clicking at (%d, %d)", x, y ) )

   -- Click location on screen
   click( Location( x, y ) )
end

-- ============ Determine current stage based on what's on screen ===========
-- @param stageIdx	The last known stage
function determineStage( stageIdx )
   local nextStageIdx = stageIdx + 1
   if nextStageIdx > numStages then nextStageIdx = 1 end

   log( "INFO", "On " .. stages[stageIdx] .. ", checking for " .. stages[nextStageIdx] )

   -- Check that this stage is the expected next first (most likely scenario).
   -- If not, then check if we haven't transitioned from the last stage
   if matchStage( nextStageIdx, true )
   then
      log( "INFO", "Successfully found next expected stage of " .. stages[nextStageIdx] )
      return nextStageIdx
   elseif matchStage( stageIdx )
   then
      log( "INFO", "Previous transition failed. Staying on " .. stages[stageIdx] )
      return stageIdx
   end

   -- Didn't find what was expected in normal flow. Check for special stages before
   -- searching (ie., transitioning to recovery mode)
   
   -- Network disconnection
   if matchStage( DISCONNECTED_SCREEN )
   then
      log( "INFO", "Found network disconnect prompt. Dismissing prompt" )
      handleReconnect( DISCONNECTED_SCREEN )
      return determineStage( stageIdx )
   elseif matchStage( DISCONNECTED_SCREEN_ALT )
   then
      log( "INFO", "Found network disconnect (alt) prompt. Dismissing prompt" )
      handleReconnect( DISCONNECTED_SCREEN_ALT )
      return determineStage( stageIdx )
   end

   -- Lapis Refill (only appears on stage 0 -> 1 transition)
   if stageIdx == STAGE_SELECT_SCREEN and matchStage( ENERGY_REFILL_SCREEN )
   then
      log( "INFO", "Found energy refill prompt" )
      handleRefillPrompt()
      if use_lapis
      then
         return determineStage( stageIdx )
      else
         log( "INFO", "Out of energy. Stopping script" )
         scriptExit( "Out of energy. Stopping script" )
      end
   elseif nextStageIdx == RESULTS_SCREEN_1 and BOTTOM_HALF:exists( "rank_up.png" )
   then
      -- Need to dismiss some extra info when ranking up
      log( "INFO", "Rank Up! Dismissing extra rank up info before continuing" )
      doClick( MIDDLE_HALF )     -- Dismiss Rank Up notification
      wait( 2 )
      doClick( MIDDLE_HALF )     -- Dismiss 100 lapis gift
      wait( 2 )
      return determineStage( stageIdx ) -- Continue with first result screen as normal
   elseif stageIdx == RESULTS_SCREEN_3 and matchStage( DAILY_STORY_COMP_SCREEN )
   then
      log( "INFO", "Found daily story quest complete prompt. Dismissing prompt" )
      handleDailyQuestsDialog()
      return determineStage( stageIdx )
   elseif matchStage( APP_CRASHED )
   then
      -- FFBE crashed. Relaunch it and figure out where we are
      log( "INFO", "FFBE crashed. Relaunching app" )
      relaunchFFBE()
      handleSplashScreen()
      return determineStage( stageIdx )
   elseif matchStage( SPLASH_SCREEN )
   then
      -- FFBE crashed and the splash screen took too long to come up.
      -- Just click somewhere in the middle of the screen and wait
      log( "INFO", "Stuck on FFBE splash screen. Continuing." )
      handleSplashScreen()
      return determineStage( stageIdx )
   elseif matchStage( RESUME_MISSION )
   then
      -- Prompt after a crash asking whether we want to resume the last mission (yes, we do)
      log( "INFO", "Found resume mission prompt" )
      handleDialog( "resume_yes.png", "resume_mission.png" )
      wait( 15 )   -- Not based on any measurement...
      return determineStage( stageIdx )
   elseif matchStage( ADDL_DATA_DOWNLAD )
   then
      -- Additional download prompt (typically happens when restarting app)
      log( "INFO", "Found additional data download prompt" )
      handleDialog( "addl_data_accept.png", "addl_data.png" )
      wait( 8 )    -- Not based on any measurement...
      return determineStage( stageIdx )
   end

   -- No idea where we are. See if we can match the snapshot to a known screen
   log( "INFO", "Unable to determine stage on current = " .. stages[stageIdx])
   for idx, _ in pairs( stages )
   do
      log( "DEBUG", "Checking screenshot against " .. stages[idx] )
      if matchStage( idx )
      then
         log( "INFO", "Determined current stage to be " .. stages[idx] .. " from search" )
         return idx
      end
      log( "DEBUG", "Match Failed" )
   end

   -- Couldn't match anything
   log( "WARN", "Failed to match current stage against known stages" )
   numFailedMatches = numFailedMatches + 1
   if numFailedMatches == 3
   then
      log( "ERR", "Failed to determine stage on last stage = " .. stages[stageIdx] )
      log( "ERR", "Saving final screenshot as 'unknown.png'" )
      local screen = getRealScreenSize()
      screen = Region( 0, 0, screen:getX(), screen:getY() )
      screen:save( "unknown.png" )
      scriptExit( "Failed to determine stage on last stage = " .. stages[stageIdx] )
   end

   -- Don't know what stage we are on and we haven't hit 3 failed in a row.
   -- Try again.
   return determineStage( stageIdx )
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
      return BOTTOM_QUARTER:exists( "next_mission.png" )
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
      return BOTTOM_QUARTER:exists( "next_res1.png" )
   elseif stageIdx == RESULTS_SCREEN_2
   then
      return TOP_HALF:exists( "unit_exp_0.png" )
   elseif stageIdx == RESULTS_SCREEN_3
   then
      return BOTTOM_QUARTER:exists( "next_res3.png", 5 )
   elseif stageIdx == ENERGY_REFILL_SCREEN
   then
      return MIDDLE_HALF:exists( "refill_prompt.png" )
   elseif stageIdx == LAPIS_CONFIRM_SCREEN
   then
      return MIDDLE_HALF:exists( "refill_confirm.png" )
   elseif stageIdx == DISCONNECTED_SCREEN
   then
      return MIDDLE_HALF:exists( "connection_error.png" )
   elseif stageIdx == DISCONNECTED_SCREEN_ALT
   then
      return MIDDLE_HALF:exists( "connection_error_alt.png" )
   elseif stageIdx == DAILY_STORY_COMP_SCREEN
   then
      return MIDDLE_HALF:exists( "story_missions.png" )
   elseif stageIdx == APP_CRASHED
   then
      -- Assuming FFBE icon is on bottom half of home screen
      return BOTTOM_HALF:exists( "ffbe_icon_text.png" )
   elseif stageIdx == SPLASH_SCREEN
   then
      return BOTTOM_HALF:exists( "splash_buttons.png" )
   elseif stageIdx == RESUME_MISSION
   then
      return MIDDLE_HALF:exists( "resume_mission.png" )
   elseif stageIdx == ADDL_DATA_DOWNLAD
   then
      return MIDDLE_HALF:exists( "addl_data.png" )
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
      -- Round 1, click first two units
      doClick( UNIT_1_REGION, true )
      doClick( UNIT_2_REGION, true )
      wait( 13 )
      
      -- Round 2, click first two units
      doClick( UNIT_1_REGION, true )
      doClick( UNIT_2_REGION, true )
      wait( 20 )

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
   local attempts = 0
   while not clicked and attempts < 10
   do
      local prompt = MIDDLE_HALF:getLastMatch()
      local roi = prompt:exists( clickPattern )
      if roi == nil
      then
         -- expected button wasn't in the last match. Try again with a new snapshot
         log( "ERR", string.format( 
            "Unable to find %s in dialog. Trying again with new snapshot (attempt number %d)",
            clickPattern, attempts ) )
         
         usePreviousSnap( false )
         MIDDLE_HALF:exists( matchPattern )
         attempts = attempts + 1
      else
         doClick( roi )
         clicked = true
      end
   end
end

-- ============ Handle Network Disconnect Dialog ===========
function handleReconnect( promptType )
   if promptType == DISCONNECTED_SCREEN
   then
      handleDialog( "ok.png", "connection_error.png" )
   else
      handleDialog( "ok.png", "connection_error_alt.png" )
   end
   wait( 2 )
   log( "INFO", "Dismissed network disconnection dialog" )
end

-- ============ Handle Energy Refill Dialog ========
function handleRefillPrompt()
   if not use_lapis
   then
      keyevent( 4 )     -- Hit back button to dismiss dialog
   else
      -- FFBE v2.0 update: The refill is now a two dialog processing
      --    1) Prompt 1 - Select to use Lapis to refill
      --    2) Prompt 2 - Confirm to use Lapis (original dialog from FFBE 1.x)
      handleDialog( "lapis_refill.png", "refill_prompt.png" )
      wait( 2 )
      matchStage( LAPIS_CONFIRM_SCREEN, true )
      handleDialog( "refill_yes.png", "refill_confirm.png" )
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
   
end

-- ============ Handle the splash screen ===========
function handleSplashScreen()
   -- Handle network failure prompts
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
-- Top level loop is to capture any exceptions. This usually happens when
-- the script has a socket timeout with the Ankulua daemon. The script will
-- exit if enough exceptions occur without a successful script iteration
stageIdx = RESULTS_SCREEN_3
while true
do
  
   -- Inner loop. Performs the actual logic of the script. It
   -- will determine which stage we're on, handle the action of that
   -- stage, and update the internal tracking variables.
   -- Wrap in a pcall(..) statement to gracefully handle an exception.
   _, err = pcall(
      function() 
         while true
         do
   
            -- Determine what stage we're in
            stageIdx = determineStage( stageIdx )

            -- Handle the current stage
            handleStage( stageIdx )
            
            -- Reset error counters
            -- Reset at end of loop so numExceptions isn't overwritten prematurely
            numFailedMatches = 0
            numExceptions = 0
         end
      end
   )
   
   -- Since we've left the processing loop, an error must have occurred.
   numExceptions = numExceptions + 1
   log( "ERROR", string.format( "Exception occurred. Num consecutive exceptions = %d", numExceptions ) )
   log( "ERROR", "Exception = \n" .. err )
   if numExceptions == EXCEPTION_THRESHOLD
   then
      log( "ERROR", "Hit exception threshold. Exiting script." )
      scriptExit( "Hit exception limit" )
   end
   
   -- Slight pause before trying again, so if it is a network/daemon issue
   -- it has time to sort itself out before the script errors out
   
   -- Do a repeat a 1 second wait 5 times to verify the wait duration is fine
   log( "DEBUG", "Start 5 second wait loop" )
   for i = 1,5
   do
      wait( 1 )
      log( "DEBUG", "1 second wait" )
   end
   log( "DEBUG", "End 5 second wait loop" )
end
