local GymClient = require('../../util/gym-http-api/binding-lua/gym_http_client')
local gum = require '../../util/gym_utilities'()
local function testGym(envName, agent, nSteps, nIterations, opt)
   local opt = opt or {}
   local base = 'http://127.0.0.1:5000'
   local client = GymClient.new(base)
   local instance_id = client:env_create(envName)
   local outdir = opt.outdir
   local video = opt.video
   local showTrajectory = opt.showTrajectory
   local force = opt.force
   local resume = opt.resume
   local renderAllSteps = opt.renderAllSteps

   local perf = require('../../util/perf')({nIterations = nSteps})
   local function run()
      -- Set up the agent given the details about the environment
      client:env_monitor_start(instance_id, outdir, force, resume, video)
      local agentOpt = opt or {}
         agentOpt.stateSpace = client:env_observation_space_info(instance_id)
         agentOpt.actionSpace = client:env_action_space_info(instance_id)
         agentOpt.nIterations = nIterations
         agentOpt.model = agent.model
         agentOpt.policy = agent.policy
         agentOpt.learningUpdate = agent.learningUpdate
         agentOpt.envDetails = gum.getStateAndActionSpecs(agentOpt.stateSpace, agentOpt.actionSpace)
      local agent = require('../../agents/gym/gym_base_agent')(agentOpt)

      local function actionSampler() return client:env_action_space_sample(instance_id) end

      for nIter=1,nIterations do
          local state = client:env_reset(instance_id)
          perf.reset()
          for i = 1, nSteps do
             local action = agent.selectAction(client, instance_id, state, envDetails, agent)

             -- TODO: clean up this if statement
             render = render == 'true' and true or false
             nextState, reward, terminal, _ = client:env_step(instance_id, action, render)
             -- set terminal to true if reached max number of steps
             if i == nSteps then terminal = true end
             agent.reward({state = state, reward = reward, terminal = terminal, nextState = nextState, nIter = nIter})
             state = nextState
             perf.addReward(nIter, reward, terminal)
             if terminal then
               state = client:env_reset(instance_id)
            end
          end
          print(nIter)
          print(perf.getSummary())
      end


      --[[
      if agentOpt.learningType == 'noBatch' then
         local trajs = {}
         local episodeRewards = torch.Tensor(nIterations):zero()
         for nIter = 1, nIterations do
            trajs[nIter] = agent.getTrajectory(client, instance_id, nSteps, renderAllSteps, agentOpt.learningType)
            for j = 1,#trajs[nIter] do
               episodeRewards[nIter] = episodeRewards[nIter] + trajs[nIter][j].reward
            end
            print('------------------')
            print('Episode: ' .. nIter)
            print('Steps: ' .. #trajs[nIter])
            print('Reward: ' .. episodeRewards[nIter])
            print('------------------')
         end
      else
         -- run the learning algorithm over a number of iterations
         for nIter = 1, nIterations do
            local trajs, timestepsTotal, epLens, epRews, tj = agent.collectTrajectories(client, instance_id, nSteps, renderAllSteps)
            local _ = agent.learn(trajs, nIter, agentOpt.envDetails, tj, agent)
            print('------------------')
            print('Iteration: ' .. nIter)
            print('NumTraj: ' .. #trajs)
            print('NumTimesteps: ' .. timestepsTotal)
            print('MaxRew: ' .. epRews:max())
            print('MeanRew: ' .. epRews:mean())
            print('MeanLen: ' .. epLens:mean())
            print "-----------------"
            if showTrajectory then
               agent.getTrajectory(client, instance_id, nSteps, showTrajectory, agentOpt.learningType)
            end
         end
      end
      ]]
      -- Dump result info to disk
      client:env_monitor_close(instance_id)

      if opt.uploadResults == true then
         -- Upload to the scoreboard.
         -- Assumes 'OPENAI_GYM_API_KEY' set on the client side
         -- client:upload() can include algorithm_id and a API key
         client:upload(outdir)
      end
      return true
   end
   if instance_id ~= nil then
      if pcall(run()) then
         print('Error on running experiment!')
      end
   else
      print('Error: No server found! Be sure to start a Gym server before running an experiment.')
   end
end
return testGym
