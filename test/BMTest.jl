module BMTest

using Base.Test
using RDatasets
import BoltzmannMachines
const BMs = BoltzmannMachines

function createsamples(nsamples::Int, nvariables::Int, samerate=0.7)
   x = round.(rand(nsamples,nvariables))
   samerange = 1:round(Int, samerate*nsamples)
   x[samerange,3] = x[samerange,2] = x[samerange,1]
   x = x[randperm(nsamples),:] # shuffle lines
   x
end

function randrbm(nvisible, nhidden, factorw = 1.0, factora = 1.0, factorb = 1.0)
   w = factorw*randn(nvisible, nhidden)
   a = factora*rand(nvisible)
   b = factorb*(0.5 - rand(nhidden))
   BMs.BernoulliRBM(w, a, b)
end

function randgbrbm(nvisible, nhidden, factorw = 1.0, factora = 1.0, factorb = 1.0, factorsd = 1.0)
   w = factorw*randn(nvisible, nhidden)
   a = factora*rand(nvisible)
   b = factorb*ones(nhidden)
   sd = factorsd*ones(nvisible)
   BMs.GaussianBernoulliRBM(w, a, b, sd)
end

function randbgrbm(nvisible, nhidden, factorw = 1.0, factora = 1.0, factorb = 1.0)
   w = factorw*randn(nvisible, nhidden)
   a = factora*rand(nvisible)
   b = factorb*ones(nhidden)
   BMs.BernoulliGaussianRBM(w, a, b)
end

function randdbm(nunits)
   nrbms = length(nunits) - 1
   dbm = BMs.BasicDBM(nrbms)
   for i = 1:nrbms
      dbm[i] = randrbm(nunits[i], nunits[i+1])
   end
   dbm
end

function logit(p::Array{Float64})
   log.(p./(1-p))
end


"""
Tests the functions for computing the activation potentials
"""
function testpotentials()
   nvisible = 3
   nhidden = 2
   nsamples = 5
   vv = rand(nsamples, nvisible)

   # Test Test activation potential of hidden nodes for BernoulliRBM
   hh = rand(nsamples, nhidden)
   rbm = BMTest.randrbm(nvisible, nhidden)
   BMs.hiddenpotential!(hh, rbm, vv)
   @test sum(abs.(hh - BMs.hiddenpotential(rbm, vv))) == 0

   # Test that activation potential of hidden nodes of a
   # Binomial2BernoulliRBM is the same as that of a BernoulliRBM
   b2brbm = BMs.Binomial2BernoulliRBM(rbm.weights, rbm.visbias, rbm.hidbias)
   hh2 = BMs.hiddenpotential(b2brbm, vv)
   @test sum(abs.(hh - hh2)) == 0
   BMs.hiddenpotential!(hh, b2brbm, vv)
   @test sum(abs.(hh - hh2)) == 0

   # Test activation potential of visible nodes for BernoulliRBM
   BMs.visiblepotential!(vv, rbm, hh)
   @test sum(abs.(vv - BMs.visiblepotential(rbm, hh))) == 0

   # Test activation potential of the visible nodes of a Binomial2BernoulliRBM
   BMs.visiblepotential!(vv, b2brbm, hh)
   @test sum(abs.(vv- BMs.visiblepotential(b2brbm, hh))) == 0

   # Test activation potential of hidden nodes for GBRBM
   hh = rand(nsamples, nhidden)
   gbrbm = BMTest.randgbrbm(nvisible, nhidden)
   BMs.hiddenpotential!(hh, gbrbm, vv)
   @test sum(abs.(hh - BMs.hiddenpotential(gbrbm, vv))) == 0

   # Test activation potential of visible nodes for GBRBM
   BMs.visiblepotential!(vv, gbrbm, hh)
   @test sum(abs.(vv - BMs.visiblepotential(gbrbm, hh))) == 0

   # Test activation potential of hidden nodes for PartitionedRBM.
   # For a PartitionedRBM consisting of BernoulliRBMs, the
   # activation potential has to be the same as the activation potential
   # of the BernoulliRBM resulting from joining the RBMs.
   nvisible2 = 7
   nhidden2 = 4
   vv = rand(nsamples, nvisible + nvisible2)
   hhpartitioned = rand(nsamples, nhidden + nhidden2)
   rbm2 = BMTest.randrbm(nvisible2, nhidden2)
   prbm = BMs.PartitionedRBM{BMs.BernoulliRBM}([rbm; rbm2])
   joinedrbm = BMs.joinrbms([rbm; rbm2])
   BMs.hiddenpotential!(hhpartitioned, joinedrbm, vv)
   @test sum(abs.(hhpartitioned - BMs.hiddenpotential(joinedrbm, vv))) == 0

   # Test activation potential of visible nodes for PartitionedRBM
   BMs.visiblepotential!(vv, prbm, hhpartitioned)
   @test sum(abs.(vv - BMs.visiblepotential(joinedrbm, hhpartitioned))) == 0
end


function rbmexactloglikelihoodvsbaserate(x::Matrix{Float64}, nhidden::Int)
   a = logit(vec(mean(x,1)))
   nvisible = length(a)
   rbm = BMs.BernoulliRBM(zeros(nvisible, nhidden), a, ones(nhidden))
   baserate = BMs.bernoulliloglikelihoodbaserate(x)
   exactloglik = BMs.loglikelihood(rbm, x, BMs.exactlogpartitionfunction(rbm))
   baserate - exactloglik
end

function bgrbmexactloglikelihoodvsbaserate(x::Matrix{Float64}, nhidden::Int)
   a = logit(vec(mean(x,1)))
   nvisible = length(a)
   bgrbm = BMs.BernoulliGaussianRBM(zeros(nvisible, nhidden), a, ones(nhidden))
   baserate = BMs.bernoulliloglikelihoodbaserate(x)
   exactloglik = BMs.loglikelihood(bgrbm, x, BMs.exactlogpartitionfunction(bgrbm))
   baserate - exactloglik
end

function gbrbmexactloglikelihoodvsbaserate(x::Matrix{Float64}, nhidden::Int)
   a = vec(mean(x,1))
   nvisible = length(a)
   sd = vec(std(x,1))
   gbrbm = BMs.GaussianBernoulliRBM(zeros(nvisible, nhidden), a, ones(nhidden), sd)
   baserate = BMs.gaussianloglikelihoodbaserate(x)
   exactloglik = BMs.loglikelihood(gbrbm, x, BMs.exactlogpartitionfunction(gbrbm))
   baserate - exactloglik
end

function test_stackrbms_preparetrainlayers()
   x = Matrix{Float64}(22, 10);
   epochs = 17
   learningrate = 0.007
   nhiddens = [7;6;5]
   learningrate1 = 0.007
   learningrate2 = 0.017
   epochs1 = 27
   epochs2 = 17

   # no layer-specific instructions
   trainlayers = Vector{BMs.TrainLayer}()
   trainlayers = BMs.stackrbms_preparetrainlayers(trainlayers, x, epochs,
         learningrate, nhiddens)
   @test length(trainlayers) == length(nhiddens)
   @test all(map(t -> t.learningrate == learningrate, trainlayers))
   @test all(map(t -> t.epochs == epochs, trainlayers))
   @test map(t-> t.nhidden, trainlayers) == nhiddens

   # layer-specific instructions without partitioning
   trainlayers = [
         BMs.TrainLayer(learningrate = learningrate1, epochs = epochs1,
               nhidden = nhiddens[1]);
         BMs.TrainLayer(learningrate = learningrate2, epochs = epochs2,
               nhidden = nhiddens[2]);
         BMs.TrainLayer(nhidden = nhiddens[3])
   ]
   trainlayers = BMs.stackrbms_preparetrainlayers(trainlayers, x, epochs,
         learningrate, Vector{Int}())
   @test length(trainlayers) == length(nhiddens)
   @test trainlayers[1].learningrate == learningrate1
   @test trainlayers[2].learningrate == learningrate2
   @test trainlayers[3].learningrate == learningrate
   @test trainlayers[1].epochs == epochs1
   @test trainlayers[2].epochs == epochs2
   @test trainlayers[3].epochs == epochs
   @test map(t-> t.nhidden, trainlayers) == nhiddens

   # partitioning
   trainlayers = [
         BMs.TrainPartitionedLayer([
            BMs.TrainLayer(learningrate = learningrate1, epochs = epochs1,
                  rbmtype = BMs.GaussianBernoulliRBM, nhidden = 3,
                  nvisible = 3);
            BMs.TrainLayer(nhidden = 4, nvisible = 7)
         ]);
         BMs.TrainLayer(nhidden = 6);
         BMs.TrainLayer(nhidden = 5)
   ]
   trainlayers = BMs.stackrbms_preparetrainlayers(trainlayers, x, epochs,
         learningrate, Vector{Int}())
   @test length(trainlayers) == length(nhiddens)
   @test trainlayers[1].parts[1].learningrate == learningrate1
   @test trainlayers[1].parts[2].learningrate == learningrate
   @test trainlayers[3].learningrate == learningrate
   @test trainlayers[1].parts[1].epochs == epochs1
   @test trainlayers[1].parts[2].epochs == epochs
   @test trainlayers[2].epochs == epochs
   @test trainlayers[3].epochs == epochs
   @test [trainlayers[1].parts[1].nhidden + trainlayers[1].parts[2].nhidden;
         trainlayers[2].nhidden; trainlayers[3].nhidden] == nhiddens

   # incorrect partitioning must not be allowed
   trainlayers[1].parts[1].nvisible = 20
   @test_throws ErrorException BMs.stackrbms_preparetrainlayers(trainlayers,
         x, epochs, learningrate, Vector{Int}())

   nothing
end

"""
    testaisvsexact(bm, percentalloweddiff)
Tests whether the exact log partition function is approximated by the value
estimated by AIS for the given Boltzmann Machine.
The test is successful, if the difference in percent of the log of the exact value
between the exact log partition function and AIS-estimated one is less than
`percentalloweddiff`.
"""
function testaisvsexact(bm::BMs.AbstractBM, percentalloweddiff::Float64;
      ntemperatures = 100, nparticles = 100)

   exact = BMs.exactlogpartitionfunction(bm)
   estimated = BMs.logpartitionfunction(bm;
         ntemperatures = ntemperatures, nparticles = nparticles)

   @test abs((exact - estimated)/exact) < percentalloweddiff / 100
end

function exactlogpartitionfunctionwithoutsummingout(dbm::BMs.BasicDBM)
   nlayers = length(dbm) + 1
   u = BMs.initcombination(dbm)
   z = 0.0
   while true
      z += exp(-BMs.energy(dbm, u))
      BMs.next!(u) || break
   end
   log(z)
end

function testsummingoutforexactloglikelihood(nunits::Vector{Int})
   x = BMTest.createsamples(1000, nunits[1]);
   dbm = BMs.stackrbms(x, nhiddens = nunits[2:end],
         epochs = 50, predbm = true, learningrate = 0.001);
   dbm = BMs.traindbm!(dbm, x,
         learningrates = [0.02*ones(10); 0.01*ones(10); 0.001*ones(10)],
         epochs = 30);
   logz = BMs.exactlogpartitionfunction(dbm)
   @test isapprox(BMs.exactloglikelihood(dbm, x, logz),
         exactloglikelihoodwithoutsummingout(dbm, x, logz))
end

function exactloglikelihoodwithoutsummingout(dbm::BMs.BasicDBM, x::Array{Float64,2},
      logz = BMs.exactlogpartitionfunction(dbm))

   nsamples = size(x,1)
   nlayers = length(dbm) + 1

   u = BMs.initcombination(dbm)
   logp = 0.0
   for j = 1:nsamples
      u[1] = vec(x[j,:])

      p = 0.0
      while true
         p += exp(-BMs.energy(dbm, u))

         # next combination of hidden nodes' activations
         BMs.next!(u[2:end]) || break
      end

      logp += log(p)
   end

   logp /= nsamples
   logp -= logz
   logp
end


function testdbmjoining()
   dbm1 = BMTest.randdbm([5;4;3])
   dbm2 = BMTest.randdbm([4;5;2])
   dbm3 = BMTest.randdbm([6;7;8])

   exactlogpartitionfunction1 = BMs.exactlogpartitionfunction(dbm1)
   exactlogpartitionfunction2 = BMs.exactlogpartitionfunction(dbm2)
   exactlogpartitionfunction3 = BMs.exactlogpartitionfunction(dbm3)

   jointdbm1 = BMs.joindbms(BMs.BasicDBM[dbm1, dbm2])
   # Test use of visibleindexes
   indexes = randperm(15)

   jointdbm2 = BMs.joindbms(BMs.BasicDBM[dbm1, dbm2, dbm3],
            [indexes[1:5], indexes[6:9], indexes[10:15]])

   @test isapprox(
               exactlogpartitionfunction1 + exactlogpartitionfunction2,
               BMs.exactlogpartitionfunction(jointdbm1))

   @test isapprox(
            exactlogpartitionfunction1 + exactlogpartitionfunction2 +
                  exactlogpartitionfunction3,
            BMs.exactlogpartitionfunction(jointdbm2))
end


"""
Tests whether the empirical loglikelihood from samples that are generated from
the exact distribution of Boltzmann machines is equal to the exact loglikelihood.
"""
function test_exactsampling()
   nsamples = 200
   x = BMs.barsandstripes(nsamples, 9)[:, 1:6]

   dbm1 = BMs.fitdbm(x; epochspretraining = 20, epochs = 15, nhiddens = [8; 5])
   BMTest.test_exactsampling(dbm1, x)

   dbm1 = BMs.fitdbm(x; epochspretraining = 20, epochs = 15, nhiddens = [6; 5; 4])
   BMTest.test_exactsampling(dbm1, x)

   rbm = BMs.fitrbm(x; epochs = 100, nhidden = 20)
   BMTest.test_exactsampling(rbm, x)
end

function test_exactsampling(bm::BMs.AbstractBM, x::Matrix{Float64};
      percentalloweddiff = 2.0)

   mbdist = BMs.MultivariateBernoulliDistribution(bm)
   exactsamples = BMs.samples(mbdist, 35000)

   emploglikexactsamples = BMs.empiricalloglikelihood(x, exactsamples)
   exactloglik = BMs.exactloglikelihood(bm, x)
   @test abs((emploglikexactsamples - exactloglik) / exactloglik) <
         percentalloweddiff / 100
end


"""
Fits a larger RBM and a DBM and tests whether the AIS estimation
yields approximately the same results, if performed parallel or not.
"""
function test_likelihoodconsistency()
   nsamples = 1000
   nvariables = 64
   x = BMs.barsandstripes(nsamples, nvariables)
   dbm = BMs.fitdbm(x; epochspretraining = 20, epochs = 15,
         nhiddens = [50; 25; 20])

   logp1 = BMs.loglikelihood(dbm, x[1:10,:];
         parallelized = false, nparticles = 300, ntemperatures = 200)
   logp2 = BMs.loglikelihood(dbm, x[1:10,:];
         parallelized = true, nparticles = 300, ntemperatures = 200)
   @test isapprox(logp1, logp2, rtol = 0.055)

   rbm1 = BMs.fitrbm(x; epochs = 20)
   logz1 = BMs.logpartitionfunction(rbm1; parallelized = false)
   logz1_2 = BMs.logpartitionfunction(rbm1; parallelized = true)
   @test isapprox(logz1, logz1_2, rtol = 0.02)

   logp1 = BMs.loglikelihood(rbm1, x, logz1)
   rbm2 = BMs.fitrbm(x; epochs = 20, nhidden = 30)
   logz2 = BMs.logpartitionfunction(rbm2)
   logp2 = BMs.loglikelihood(rbm2, x, logz2)

   samplemeanrbm =
         BMs.BernoulliRBM(zeros(nvariables,1), vec(mean(x, 1)), zeros(1))
   samplemeanrbm2 =
         BMs.BernoulliRBM(zeros(rbm1.weights), vec(mean(x, 1)), zeros(rbm1.hidbias))

   # Annealing between two RBMs with zero weights
   @test isapprox(
         BMs.logmeanexp(BMs.aislogimpweights(samplemeanrbm, samplemeanrbm2)),
         (BMs.logpartitionfunctionzeroweights(samplemeanrbm2) -
               BMs.logpartitionfunctionzeroweights(samplemeanrbm)))

   # Annealing from RBM to RBM with sample mean and zero weights
   @test abs(logz1 - BMs.logpartitionfunctionzeroweights(samplemeanrbm) -
         BMs.logmeanexp(BMs.aislogimpweights(samplemeanrbm, rbm1))) <
               logz1 * 0.013

   # Annealing from one RBM to another RBM: Compare partition functions ...
   logimpweights = BMs.aislogimpweights(rbm1, rbm2;
         ntemperatures = 1000, nparticles = 200, burnin = 10)
   @test abs(BMs.logmeanexp(logimpweights) - (logz2 - logz1)) <
         max(logz2, logz1) * 0.03
   # ... and loglikelihood
   lldiff2 = BMs.loglikelihooddiff(rbm1, rbm2, x, logimpweights)
   lldiff1 = logp1 - logp2
   # very weak test, TODO: check and improve
   @test sign(lldiff1) == sign(lldiff2)
end


"""
Tests the likelihood estimation approaches for GaussianBernoulliRBMs
and alternative GaussianBernoulliRBMs.
"""
function test_likelihoodconsistency_gaussian(gbrbmtype::Type{GBRBM}
      ) where GBRBM <: Union{BMs.GaussianBernoulliRBM, BMs.GaussianBernoulliRBM2}

   x = BMs.curvebundles(nperbundle = 300, nvariables = 10,
         nbundles = 4)

   gbrbm1 = BMs.fitrbm(x; nhidden = 30, rbmtype = gbrbmtype,
         cdsteps = 10,
         pcd = false,
         learningrate = 0.001, epochs = 50,
         sdlearningrate = 0.00001)

   datainitrbm = GBRBM(zeros(size(x,2), 1),
         vec(mean(x,1)), [0.0], vec(std(x,1)))


   # Compare estimated difference of log partition functions to difference
   # between estimation and exact log partition function of GBRBM with zero weights
   logz1 = BMs.logpartitionfunction(gbrbm1)
   @test abs(logz1 - BMs.logpartitionfunctionzeroweights(datainitrbm) -
         BMs.logmeanexp(BMs.aislogimpweights(datainitrbm, gbrbm1,
               nparticles = 200, ntemperatures = 200))) < 0.03 * logz1

   gbrbm2 = BMs.fitrbm(x; nhidden = 15, rbmtype = gbrbmtype,
         cdsteps = 10,
         learningrate = 0.001, epochs = 100,
         sdlearningrates = [fill(0.0, 30); fill(0.00001, 300)])

   logz2 = BMs.logpartitionfunction(gbrbm2)

   logdiffimpweights = BMs.aislogimpweights(gbrbm1, gbrbm2)
   logzdiff = BMs.logmeanexp(logdiffimpweights)

   # Annealing from one RBM to another RBM: Compare partition functions ...
   @test abs(logzdiff - (logz2 - logz1)) < max(logz2, logz1) * 0.03
   # ... and loglikelihood
   logp1 = BMs.loglikelihood(gbrbm1, x, logz1)
   logp2 = BMs.loglikelihood(gbrbm2, x, logz2)
   lldiff2 = BMs.loglikelihooddiff(gbrbm1, gbrbm2, x, logdiffimpweights)
   lldiff1 = logp1 - logp2
   # very weak test, TODO: check and improve
   @test sign(lldiff1) == sign(lldiff2)
end


"
Tests whether the log-likelihood of Binomial2BernoulliRBMs is approximately
equal to the empirical loglikelihood of data generated by the models, and whether
the partition function estimated by AIS is near the exact value.
"
function test_b2brbm()
   x = BMTest.createsamples(100, 4) + BMTest.createsamples(100, 4)
   b2brbm = BMs.fitrbm(x, rbmtype = BMs.Binomial2BernoulliRBM, epochs = 150,
         nhidden = 4, learningrate = 0.001)
   testlikelihoodempirically(b2brbm, x; percentalloweddiff = 1.0)
end


function test_rbm()
   x = BMTest.createsamples(100, 4)
   rbm = BMs.fitrbm(x, epochs = 30,
         nhidden = 4, learningrate = 0.001)
   testlikelihoodempirically(rbm, x)
end

function test_gbrbm(gbrbmtype::Type{GBRBM}
      ) where GBRBM <:Union{BMs.GaussianBernoulliRBM, BMs.GaussianBernoulliRBM2}

   x = BMs.curvebundles(nperbundle = 300, nvariables = 10,
         nbundles = 4)
   gbrbm = BMs.fitrbm(x; nhidden = 15, rbmtype = gbrbmtype,
         cdsteps = 10,
         pcd = false,
         learningrate = 0.001, epochs = 50,
         sdlearningrate = 0.00001)

   logz = BMs.logpartitionfunction(gbrbm; parallelized = true,
         ntemperatures = 500, nparticles = 500)
   estloglik = BMs.loglikelihood(gbrbm, x, logz)
   exactloglik = BMs.exactloglikelihood(gbrbm, x)
   @test abs((exactloglik - estloglik) / exactloglik) < 2.5 / 100
end

function test_rbm_monitoring(gbrbmtype::Type{GBRBM}
      ) where GBRBM <:Union{BMs.GaussianBernoulliRBM, BMs.GaussianBernoulliRBM2}

   x = BMs.curvebundles(nperbundle = 20, nvariables = 5,
      nbundles = 4)

   # Test some more options and monitoring
   monitor = BMs.Monitor()
   datadict = BMs.DataDict("Small subset" => x[1:3, :])
   gbrbm = BMs.fitrbm(x; nhidden = 5, rbmtype = gbrbmtype,
         learningrate = 0.000001, epochs = 20,
         batchsize = 10,
         pcd = false,
         sdlearningrate = 0.000000001,
         monitoring = (rbm, epoch) -> begin
            if epoch == 10 || epoch == 20
               BMs.monitorexactloglikelihood!(monitor, rbm, epoch, datadict)
               BMs.monitorreconstructionerror!(monitor, rbm, epoch, datadict)
            end
         end)
   nothing
end


function test_mdbm_rbm_b2brbm()
   nsamples = 100
   nvariables = 4

   x1 = BMTest.createsamples(nsamples, nvariables) +
         BMTest.createsamples(nsamples, nvariables);
   x2 = BMTest.createsamples(nsamples, nvariables);
   x = hcat(x1, x2);
   trainlayers1 = [
         BMs.TrainPartitionedLayer([
            BMs.TrainLayer(rbmtype = BMs.Binomial2BernoulliRBM,
                  nvisible = nvariables, nhidden = nvariables - 1,
                  learningrate = 0.0015);
               BMs.TrainLayer(rbmtype = BMs.BernoulliRBM,
                  nvisible = nvariables, nhidden = nvariables)
         ]);
         BMs.TrainLayer(nhidden = nvariables);
         BMs.TrainLayer(nhidden = 3)]

   dbm1 = BMs.fitdbm(x, epochs = 15,
         epochspretraining = 15,
         learningratepretraining = 0.001,
         pretraining = trainlayers1)

   BMTest.testlikelihoodempirically(dbm1, x; percentalloweddiff = 5.5,
         ntemperatures = 300, nparticles = 300)

   # partitioned second layer
   trainlayers2 = [
         trainlayers1[1],
         BMs.TrainPartitionedLayer([
            BMs.TrainLayer(nhidden = 3);
            BMs.TrainLayer(nhidden = 2)
         ]),
         BMs.TrainLayer(nhidden = 4),
         BMs.TrainLayer(nhidden = 3)
   ]

   dbm2 = BMs.fitdbm(x, pretraining = trainlayers2)
   BMTest.testlikelihoodempirically(dbm2, x; percentalloweddiff = 6.3,
         ntemperatures = 300, nparticles = 300)
end


function testlikelihoodempirically(rbm::BMs.AbstractRBM, x::Matrix{Float64};
      percentalloweddiff = 0.5, ntemperatures::Int = 100, nparticles::Int = 100)

   logz = BMs.logpartitionfunction(rbm; parallelized = true,
      nparticles = nparticles, ntemperatures = ntemperatures)
   estloglik = BMs.loglikelihood(rbm, x, logz)
   exactloglik = BMs.exactloglikelihood(rbm, x)
   @test abs((exactloglik - estloglik) / exactloglik) < percentalloweddiff / 100

   emploglik = BMs.empiricalloglikelihood(rbm, x, 1000000)
   @test abs((exactloglik - emploglik) / exactloglik) < percentalloweddiff / 100
end

function testlikelihoodempirically(dbm::BMs.MultimodalDBM, x::Matrix{Float64};
      percentalloweddiff = 0.5, ntemperatures::Int = 100, nparticles::Int = 100)

   emploglik = BMs.empiricalloglikelihood(dbm, x, 1000000)
   estloglik = BMs.loglikelihood(dbm, x; parallelized = true,
         ntemperatures = ntemperatures, nparticles = nparticles)
   exactloglik = BMs.exactloglikelihood(dbm, x)
   @test abs((exactloglik - emploglik) / exactloglik) < percentalloweddiff / 100
   @test abs((exactloglik - estloglik) / exactloglik) < percentalloweddiff / 100
end


"""
Test DBMs with Gaussian visible nodes.
"""
function test_mdbm_gaussianvisibles()

   x = convert(Matrix{Float64}, RDatasets.dataset("datasets", "iris")[1:4])

   datadict = BMs.DataDict("x" => x)

   monitor1 = BMs.Monitor()
   trainlayers = [
         BMs.TrainLayer(rbmtype = BMs.GaussianBernoulliRBM,
               nhidden = 4,
               sdlearningrate = 0.000001,
               monitoring = (rbm, epoch) -> begin
                  BMs.monitorexactloglikelihood!(monitor1, rbm, epoch, datadict)
               end);
         BMs.TrainLayer(nhidden = 4);
         BMs.TrainLayer(nhidden = 4)]

   learningrates = [0.02*ones(10); 0.01*ones(10); 0.001*ones(10)]

   seed = round(Int, rand()*typemax(Int), RoundDown)
   srand(seed)
   dbm1 = BMs.stackrbms(x, epochs = 20, predbm = true, learningrate = 0.001,
         trainlayers = trainlayers)
   # BMs.BMPlots.plotevaluation(monitor1, BMs.monitorexactloglikelihood)
   dbm1 = BMs.traindbm!(dbm1, x,
         learningrates = learningrates,
         epochs = 30);

   srand(seed)
   dbm2 = BMs.fitdbm(x, epochs = 30,
         epochspretraining = 20,
         learningratepretraining = 0.001,
         pretraining = trainlayers,
         learningrates = learningrates)

   # first and second dbm must be equal
   @test length(dbm1) == length(dbm2)
   @test isapprox(dbm1[1].sd, dbm2[1].sd)
   for i in 1:length(dbm1)
      @test isapprox(dbm1[i].weights, dbm2[i].weights)
      @test isapprox(dbm1[i].visbias, dbm2[i].visbias)
      @test isapprox(dbm1[i].hidbias, dbm2[i].hidbias)
   end

   # Test AIS
   BMTest.testaisvsexact(dbm1, 0.6)

   # Test exact likelihood vs estimated likelihood
   estloglik = BMs.loglikelihood(dbm1, x; nparticles = 400, ntemperatures = 200)
   exactloglik = BMs.exactloglikelihood(dbm1, x)
   @test abs((exactloglik - estloglik) / exactloglik) < 3.5 / 100

   nothing
end


end # of module BMTest
