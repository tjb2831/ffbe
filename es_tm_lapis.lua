-- Macro to farm Earth Shrine - Entrance.
-- Assumptions:
--    1) The script is started on the Earth Shrine stage select screen
--    2) The TM team is the default team
--    3) All friend units are filtered out by the current friend filter
--    4) The user wants to use lapis refills
--    5) The TM team can auto through the ES entrance units
--    6) (Toggleable in source) The user wants Zidane to do steal instead of attack

-- ======= Settings ===========
-- Use 1536x2048 as comparison dimensions
Settings:setCompareDimension(true, 1536)  -- True flag denotes width
Settings:setCompareDimension(false, 2048) -- False flag denotes height

-- Script (and images) use 1536x2048 as screen dims
Settings:setScriptDimension(true, 1536)
Settings:setScriptDimension(false, 2048)

-- Settings used by app logic
transition_jitter = true   -- Add some random delta to screen transitions
do_steal = true
use_lapis = true
do_logging = true
logfile = nil

-- Seed the PRNG if we're adding jitter to click pauses
if transition_jitter
then
   math.randomseed( os.time() )
end

-- Open log file
if do_logging
then
   logfile = io.open( "/sdcard/Ankulua/ffbe/ffbe_log.txt", "a" )
   if logfile
   then
      io.output( logfile )
      io.write( os.date( "\n -- Starting script on %d %b %Y at %H:%M:%S\n" ) )
      io.stdout:write( "Using ffbe_log.txt as logfile\n" )
   else
      do_logging = false
      io.stdout:write( "Could not open logfile. No logging performed\n" )
   end
end

-- ======== Wait for given image to appear ==========
function waitForImg( img, waitTime )
   jitter = 0
   if transition_jitter and waitTime > 0 then
      jitter = math.random() * 3
   end

   return exists( img, waitTime + jitter )
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
   click( Location( x, y ) )
   waitTime = nextWait

   if do_logging
   then
      io.write( string.format( "Click at (%d, %d)\n", x, y ) )
   end
end

-- ========== Main Program ==========
running = true
waitTime = nil    -- How long to wait for next click
while running
do
   
   -- Find the Earth Shrine entrance button (stage selection; NOT world map)
   waitTime = 3
   if waitForImg( "es_entrance.png", waitTime )
   then
      clickLastImg( 2 )
   else
      running = false
   end

   -- Check for "No Energy" (refill popup)
   if running and waitForImg( "refill_yes.png", waitTime )
   then
      if use_lapis
      then
         clickLastImg( 4 )
      else
         running = false
      end
      -- No 'else failure' here. We could just not need to refill energy
   end

   -- Check for "Next" button (mission screen)
   if running and waitForImg( "next.png", waitTime )
   then
      clickLastImg( 4 )
   else
      running = false
   end

   -- Check for "Depart without companion" button (friend select screen)
   if running and waitForImg( "depart_no_comp.png", waitTime )
   then
      clickLastImg( 2 )
   else
      running = false
   end

   -- Check for "Depart" button (team selection screen)
   if running and waitForImg( "depart.png", waitTime )
   then
      clickLastImg( 7 )
   else
      running = false
   end

   -- Check for "Auto" button (in-battle screen)
   if running and waitForImg( "auto.png", waitTime )
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
               x_start = knob:getX() + math.random( 9 ) + 2
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
               if waitForImg( "steal.png", 0.5 )
               then
                  clickLastImg( 0.5 )
               else
                  do_steal = false
                  waitTime = 0
                  keyevent( 3 )

                  if do_logging
                  then
                     io.write( "Failed to find steal image. Hitting 'back' and cancelling steal\n" )
                  end
               end
            else
               -- Couldn't find knob. Stop stealing and go back to return to main battle screen
               do_steal = false
               waitTime = 0
               keyevent( 3 )     -- 'Back' key will close the Zidane skills menu

               if do_logging
               then
                  io.write( "Failed to find skills scrollbar knob. Hitting 'back' and cancelling steal\n" )
               end
            end
            
         else
            -- Failed to get zidane image. Stop trying to steal
            do_steal = false
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
         click( Location( x1, y1 ) )   -- Auto on
         os.execute( "sleep " .. tonumber( 2 ) )
         click( Location( x2, y2 ) )   -- Auto off
         waitTime = 8

         if do_logging
         then
            io.write( string.format( "Toggled Auto with clicks at (%d, %d) and (%d, %d)\n",
               x1, y1, x2, y2 ) )
         end
      else
         running = false
      end
   else
      running = false
   end   -- running and get 'auto.png'

   -- Wait for the second round
   if running then os.execute( "sleep " .. tonumber(waitTime) ) end
   waitTime = 0

   -- Click 'Repeat' (in-battle, second round)
   if running and waitForImg( "repeat.png", waitTime )
   then
      clickLastImg( 20 )
   else
      running = false
   end

   -- Wait for "Next" button (Results screen 1; exp, gil, rank)
   if running and waitForImg( "next.png", waitTime )
   then
      clickLastImg( 3 )
   else
      running = false
   end

   -- Wait for next screen (no button to wait for)
   if running then os.execute( "sleep " .. tonumber( waitTime ) ) end

   -- Click anywhere (Results screen 2; character exp, tm, lb)
   if running
   then
      local screen = getAppUsableScreenSize()
      local x = math.random( screen:getX() )
      local y = math.random( screen:getY() )
      click( Location( x, y ) )
      waitTime = 3

      if do_logging
      then
         io.write( string.format( "Clicked screen at (%d, %d)\n", x, y ) )
      end
   end

   -- Wait for "Next" button (Results screen 3; materials)
   if running and waitForImg( "next.png", waitTime )
   then
      clickLastImg( 0 )
   else
      running = false
   end

   if do_logging
   then
      io.write("\n")
      io.flush()
   end

   -- End of run. Wait time reset at top of loop

end   -- while running
