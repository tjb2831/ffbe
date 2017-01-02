-- Macro to farm Earth Shrine - Entrance.
-- Assumptions:
--    1) The script is started on the Earth Shrine stage select screen
--    2) The TM team is the default team
--    3) All friend units are filtered out by the current friend filter
--    4) The TM team can auto through the ES entrance units
--    5) The Ankulua start/stop button is on the top edge of the screen (no lower than 200 px in y;
--       x dim doesn't matter)
--    6) (Toggleable in source) The user wants to use lapis refills
--    7) (Toggleable in source) The user wants Zidane to do steal instead of attack

-- ======= Settings ===========
-- Use 1536x2048 as comparison dimensions
Settings:setCompareDimension(true, 1536)  -- True flag denotes width
Settings:setCompareDimension(false, 2048) -- False flag denotes height

-- Script (and images) use 1536x2048 as screen dims
Settings:setScriptDimension(true, 1536)
Settings:setScriptDimension(false, 2048)

-- Settings used by app logic
transition_jitter = true   -- Add some random delta to screen transitions
do_steal = false           -- Whether the user wants to use steal with Zidane
steal_char = "zidane"      -- Which character to steal with (currently unused)
steal_performed = false    -- True if the steal ability is actively being used
use_lapis = true           -- Refill energy with lapis when we run out
do_logging = false         -- Log click events to file
has_unstable_inet = true   -- Set to true to handle connection error popups
highlight_clicks = false   -- Highlight the click location for a few seconds (adds notable delay)
highlight_duration = 2     -- Number of seconds to highlight clicks
logfile = nil              -- handle to log

-- ======== Wait for given image to appear ==========
function waitForImg( img, waitTime )
   local trials = 3
   local matched = nil
   while not matched and trials > 0
   do
      
      matched = exists( img, waitTime )

      -- Extra check for connectivity problems
      if has_unstable_inet and not matched
      then
         matched = exists( "connection_error.png", 1 )
         if matched
         then
            -- Click "OK" button.
            -- Upper left XY = 370, 370 px
            -- Width x Height = 380x100 px
            local x = matched:getX() + math.random( 370, 370 + 380 )
            local y = matched:getY() + math.random( 370, 370 + 100 )
            highlighted_click( x, y )
            
            -- Reset loop counter and match
            trials = 4
            matched = nil
            
            if do_logging
            then
               io.write( "Connection error found. Dismissing dialog\n" )
               io.write( string.format( "Click at (%d, %d)\n", x, y ) )
            end
         end
      end

      trials = trials - 1
   end

   -- Add some random lag between clicks
   if transition_jitter and matched and waitTime > 0 then
      local jitter = math.random()
      wait( jitter )
   end

   if do_logging
   then
      if matched
      then
         io.write( string.format( "Found %s in %d tries\n", img, 3 - trials ) )
      else
         io.write( string.format( "Failed to find %s\n", img ) )
      end
   end

   return matched
end

-- ========= Get randomized X-Y coords of last match (for clicking) ========
function getRandomXY()
   lastMatch = getLastMatch()
   x_min = lastMatch:getX()
   x_max = x_min + lastMatch:getW()
   y_min = lastMatch:getY()
   y_max = y_min + lastMatch:getH()

   return math.random( x_min, x_max ), math.random( y_min, y_max )
end

-- ========= Click the last matched image at a random XY coord ========
function clickLastImg( nextWait )
   local x, y = getRandomXY()
   highlighted_click( x, y )
   waitTime = nextWait

   if do_logging
   then
      io.write( string.format( "Click at (%d, %d)\n", x, y ) )
   end
end

-- ========== Specialized click method ===========
function highlighted_click( x, y )
   -- Highlight the 50x50 region around the click, if desired
   if highlight_clicks
   then
      local hl_region = Region( x - 25, y - 25, 50, 50 )
      hl_region:highlight( 2 )
   end

   -- Click the actual point
   local click_pt = Location( x, y )
   click( click_pt )
end

-- ========== Show dialog for user preferences =========
function getUserPrefs()
   dialogInit()

   -- Add random lag between button clicks (timing jitter)
   addCheckBox( "transition_jitter", "Random button click delay", true )
   newRow()

   -- Perform steal actions in battle
   addCheckBox( "do_steal", "Use steal in battle", false )
   local steal_users = { "Zidane" }    -- Currently only support Zidane
   newRow()
   addTextView( "Character using steal: " )
   addSpinner( "steal_char", steal_users, steal_users[0] )
   newRow()

   -- Use lapis when out of energy
   addCheckBox( "use_lapis", "Use lapis to refill energy", true )
   newRow()

   -- Unstable internet check
   addCheckBox( "has_unstable_inet", "Check for network disconnection", false )
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
   addEditText( "logfile", "ffbe_log.txt" )
   
   -- Show the dialog
   dialogShow( "Earth Shrine Farm Settings" )
   
end

-- ========== Initialization ========
function init()

   -- Get user settings
   getUserPrefs()

   -- Seed the PRNG if we're adding jitter to click pauses
   if transition_jitter
   then
      math.randomseed( os.time() )
   end

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
                     "\tPerform steal = %s\n" ..
                     "\tSteal character = %s\n" ..
                     "\tRefill energy with lapis = %s\n" ..
                     "\tUnstable internet = %s\n" ..
                     "\tHighlight clicks = %s\n" ..
                     "\tHighlight duration = %.02f\n" ..
                     "-- End Settings\n",
                     ( transition_jitter and "true" or "false" ),
                     ( do_steal and "true" or "false" ),
                     ( do_steal and steal_char or "--" ),
                     ( use_lapis and "true" or "false" ),
                     ( has_unstable_inet and "true" or "false" ),
                     ( highlight_clicks and "true" or "false" ),
                     ( highlight_clicks and highlight_duration or "--" )
                     )
                  )

      else
         do_logging = false
      end
   end

   -- Make highlights yellow and semi-translucent
   if highlight_clicks
   then
      setHighlightStyle( 0x8fffff00, true )
   end
end

-- ========== Main Program ==========
steal_performed = false    -- Internal flag for if a steal is actively being used
waitTime = nil    -- How long to wait for next click

-- Initialize with user prefs
init()

-- Main processing loop
while true
do

   -- Reset the steal flag 
   steal_performed = false
   
   -- Find the Earth Shrine entrance button (stage selection; NOT world map)
   -- Wrap in a loop in case the story missions daily quest popup appears
   waitTime = 4
   while true
   do
      if waitForImg( "es_entrance.png", waitTime )
      then
         clickLastImg( 2 )
         break
      elseif waitForImg( "story_missions.png", 1 )
      then
         -- "Close" button is at about XY = 125, 865 px
         -- "Close" button width x height is about 300x80 px
         local matched = getLastMatch()
         local x = matched:getX() + math.random( 125, 125 + 300 )
         local y = matched:getY() + math.random( 865, 865 + 80 )
         highlighted_click( x, y )
         if do_logging
         then
            io.write( "Closing daily quest dialog\n" )
            io.write( string.format( "Click at (%d, %d)\n", x, y ) )
         end
      else
         if do_logging
         then
            io.write( "Unable to find es_entrance or daily quest dismissal button\n" )
            io.flush()
         end
         scriptExit( "Unable to find es_entrance or daily quest dismissal button" )
      end
   end


   -- Check for "Next" button (mission screen)
   -- Wrap in a loop in case the 'refill energy' dialog appears
   while true
   do
      -- If the "Next" button is there, we have the energy to continue
      if waitForImg( "next.png", waitTime )
      then
         clickLastImg( 4 )
         break
      elseif waitForImg( "refill_yes.png", waitTime )
      then
         if use_lapis
         then
            clickLastImg( 4 )
            break
         else
            if do_logging
            then
               io.write( "Out of energy and not using lapis. Quitting script.\n" )
               io.flush()
            end
            scriptExit( "Out of energy" )
         end
      else
         -- No "Next" button or "Refill" button
         if do_logging
         then
            io.write( "Unable to find next or refill button\n" )
            io.flush()
         end
         scriptExit( "Unable to find next or refill button" )
      end
   end

   -- Check for "Depart without companion" button (friend select screen)
   if waitForImg( "depart_no_comp.png", waitTime )
   then
      clickLastImg( 2 )
   else
      if do_logging
      then
         io.write( "Unable to find the No Companions button\n" )
         io.flush()
      end
      scriptExit( "Unable to find the No Companions button" )
   end

   -- Check for "Depart" button (team selection screen)
   if waitForImg( "depart.png", waitTime )
   then
      clickLastImg( 7 )
   else
      if do_logging
      then
         io.write( "Unable to find Depart button\n" )
         io.flush()
      end
      scriptExit( "Unable to find the Depart button" )
   end

   -- Check for "Auto" button (in-battle screen)
   if waitForImg( "auto.png", waitTime )
   then
      if do_steal
      then
         if waitForImg( "zidane.png", 0.5 )
         then

            -- Swipe right to bring up zidane's skills.
            -- Move from random spot on left edge to random spot on right edge,
            -- with some variance in y-coords to simulate imperfect human
            local zidaneImg = getLastMatch()
            local y_start = math.random( zidaneImg:getY(), zidaneImg:getY() + zidaneImg:getH() - 10 )
            local y_stop = y_start + ( math.random( 5 ) - 3 )
            local x_start = zidaneImg:getX() + math.random( 10 )
            local x_stop = zidaneImg:getX() + zidaneImg:getW() - math.random( 5 )
            swipe( Location( x_start, y_start ), Location( x_stop, y_stop ) )

            if do_logging
            then
               io.write( string.format( "Swiped from (%d, %d) to (%d, %d)\n",
                  x_start, y_start, x_stop, y_stop ) )
            end

            -- Randomize the drag drop params (because of paranoia)
            setDragDropTiming( math.random( 750, 1250), math.random( 250, 1000 ) )
            setDragDropStepCount( math.random( 10, 40 ) )
            setDragDropStepInterval( math.random( 10, 50 ) )

            -- Drag knob in skills scrollbar to bottom
            if waitForImg( "skills_scroll_knob.png", 1 )
            then
               local knob = getLastMatch()
               local screen = getAppUsableScreenSize()
               x_start = knob:getX() + math.random( 9 ) + 10
               x_stop = x_start + ( math.random( 3 ) - 2 )
               y_start = knob:getY() + math.random( 20 )
               y_stop = screen:getY()
               dragDrop( Location( x_start, y_start ), Location( x_stop, y_stop ) )
               
               if do_logging
               then
                  io.write( string.format( "Drag drop from (%d, %d) to (%d, %d)\n",
                     x_start, y_start, x_stop, y_stop ) )
               end

               -- Click the steal ability
               if waitForImg( "steal.png", 1 )
               then
                  clickLastImg( 1 )
                  steal_performed = true
               else
                  waitTime = 0
                  keyevent( 4 )

                  if do_logging
                  then
                     io.write( "Failed to find steal image. Hitting 'back' and cancelling steal\n" )
                  end
               end
            else
               -- Couldn't find knob. Stop stealing and go back to return to main battle screen
               waitTime = 0
               keyevent( 4 )     -- 'Back' key will close the Zidane skills menu

               if do_logging
               then
                  io.write( "Failed to find skills scrollbar knob. Hitting 'back' and cancelling steal\n" )
               end
            end
            
         else
            -- Failed to get zidane image. Stop trying to steal
            waitTime = 0

            if do_logging
            then
               io.write( "Failed to find Zidane image. Cancelling steal procedure\n" )
            end
         end
      end -- do_steal

      -- Click auto button on and off.
      -- Extra check here so auto is last thing matched, in case of steal branch
      if waitForImg( "auto.png", waitTime )
      then
         local x1, y1 = getRandomXY()
         local x2, y2 = getRandomXY()
         highlighted_click( x1, y1 )   -- Auto on
         if steal_performed
         then
            wait( 2 )
            highlighted_click( x2, y2 )   -- Auto off
         end
         waitTime = 8

         if do_logging
         then
            io.write( string.format( "Toggled Auto with clicks at (%d, %d) and (%d, %d)\n",
               x1, y1, x2, y2 ) )
         end
      else
         if do_logging
         then
            io.write( "Unable to find Auto button\n" )
            io.flush()
         end
         scriptExit( "Unable to find Auto button" )
      end
   else
      if do_logging
      then
         io.write( "Unable to find Auto button\n" )
         io.flush()
      end
      scriptExit( "Unable to find Auto button" )
   end   -- get 'auto.png'

   -- Wait for the second round
   wait( waitTime )
   waitTime = 0

   -- Click 'Repeat' if steal was performed, or just wait for round to end
   -- (In-Battle screen, round 2)
   if steal_performed
   then
      if waitForImg( "repeat.png", waitTime )
      then
         clickLastImg( 20 )
      else
         if do_logging
         then
            io.write( "Unable to find Repeat button\n" )
            io.flush()
         end
         scriptExit( "Unable to find Repeat button" )
      end
   else
      waitTime = 20
   end


   -- Wait for "Next" button (Results screen 1; exp, gil, rank)
   if waitForImg( "next.png", waitTime )
   then
      clickLastImg( 3 )
   else
      if do_logging
      then
         io.write( "Unable to find Next button\n" )
         io.flush()
      end
      scriptExit( "Unable to find Next button" )
   end

   -- Wait for next screen (no button to wait for)
   wait( waitTime )

   -- Click anywhere (Results screen 2; character exp, tm, lb)
   do
      local screen = getAppUsableScreenSize()
      local x = math.random( screen:getX() )
      local y = math.random( 200, screen:getY() )
      highlighted_click( x, y )
      waitTime = 3

      if do_logging
      then
         io.write( string.format( "Clicked screen at (%d, %d)\n", x, y ) )
      end
   end

   -- Wait for "Next" button (Results screen 3; materials)
   if waitForImg( "next.png", waitTime )
   then
      clickLastImg( 0.25 )
   else
      if do_logging
      then
         io.write( "Unable to find Next button\n" )
         io.flush()
      end
      scriptExit( "Unable to find Next button" )
   end

   if do_logging
   then
      io.write("\n")
      io.flush()
   end

   -- End of run. Wait time reset at top of loop

end   -- while main processing loop
