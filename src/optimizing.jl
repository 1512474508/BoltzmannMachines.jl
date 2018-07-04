abstract type AbstractOptimizer{R<:AbstractRBM}
end

abstract type
      AbstractLoglikelihoodOptimizer{R<:AbstractRBM} <: AbstractOptimizer{R}
end

struct NoOptimizer <: AbstractOptimizer{AbstractRBM}
end

mutable struct LoglikelihoodOptimizer{R<:AbstractRBM} <: AbstractLoglikelihoodOptimizer{R}
   gradient::R
   negupdate::Matrix{Float64}
   learningrate::Float64
   sdlearningrate::Float64
end

function LoglikelihoodOptimizer(;
      learningrate::Float64 = 0.0, sdlearningrate::Float64 = 0.0)

   LoglikelihoodOptimizer(NoRBM(), Matrix{Float64}(0,0),
         learningrate, sdlearningrate)
end

function LoglikelihoodOptimizer(rbm::R;
      learningrate::Float64 = 0.0, sdlearningrate::Float64 = 0.0) where {R<:AbstractRBM}

   LoglikelihoodOptimizer{R}(deepcopy(rbm), Matrix{Float64}(size(rbm.weights)),
         learningrate, sdlearningrate)
end


mutable struct BeamAdversarialOptimizer{R<: AbstractRBM} <: AbstractOptimizer{R}
   gradient::R
   negupdate::Matrix{Float64}
   critic::Vector{Float64}
   learningrate::Float64
   sdlearningrate::Float64
   knearest::Int
end


struct CombinedOptimizer{R<: AbstractRBM,
         G1 <: AbstractOptimizer{R},
         G2 <: AbstractOptimizer{R}} <: AbstractOptimizer{R}

   part1::G1
   part2::G2
   gradient::R
   weight1::Float64
   learningrate::Float64
   sdlearningrate::Float64
end


function beamoptimizer(;learningrate::Float64 = 0.05,
      sdlearningrate::Float64 = 0.0,
      adversarialweight::Float64 = 0.1,
      knearest::Int = 5)

   llstep = LoglikelihoodOptimizer(
         learningrate = learningrate, sdlearningrate = sdlearningrate)
   advstep = BeamAdversarialOptimizer(
         NoRBM(), Matrix{Float64}(0,0), Vector{Float64}(),
         learningrate, sdlearningrate, knearest)

   CombinedOptimizer(advstep, llstep, NoRBM(), adversarialweight,
         learningrate, sdlearningrate)
end


function initialized(optimizer::AbstractOptimizer, rbm::AbstractRBM)
   # do nothing
end

function initialized(optimizer::LoglikelihoodOptimizer, rbm::R
      ) where {R <: AbstractRBM}

   LoglikelihoodOptimizer(deepcopy(rbm),
         Matrix{Float64}(size(rbm.weights)),
         optimizer.learningrate, optimizer.sdlearningrate)
end

function initialized(optimizer::CombinedOptimizer, rbm::R
      ) where {R <: AbstractRBM}

   CombinedOptimizer(initialized(optimizer.part1, rbm),
         initialized(optimizer.part2, rbm),
         deepcopy(rbm),
         optimizer.weight1, optimizer.learningrate, optimizer.sdlearningrate)
end

function initialized(optimizer::BeamAdversarialOptimizer{R1}, rbm::R2
      ) where {R1 <: AbstractRBM, R2 <: AbstractRBM}

   BeamAdversarialOptimizer{R2}(deepcopy(rbm),
         Matrix{Float64}(size(rbm.weights)),
         Vector{Float64}(),
         optimizer.learningrate, optimizer.sdlearningrate,
         optimizer.knearest)
end


"""
    computegradient!(optimizer, v, vmodel, h, hmodel, rbm)
Computes the gradient of the RBM `rbm` given the
the hidden activation `h` induced by the sample `v`
and the vectors `vmodel` and `hmodel` generated by sampling from the model.

!!!  note
      This function may alter all arguments except for `rbm` and `hmodel`.
     `hmodel` must not be changed by implementations of `computegradient!`
     since the persistent chain state is stored there.
"""
function computegradient!(
      optimizer::AbstractLoglikelihoodOptimizer{R},
      v::M, vmodel::M, h::M, hmodel::M, rbm::R
      ) where {R <: AbstractRBM, M <: AbstractArray{Float64, 2}}

   At_mul_B!(optimizer.gradient.weights, v, h)
   At_mul_B!(optimizer.negupdate, vmodel, hmodel)
   optimizer.gradient.weights .-= optimizer.negupdate

   optimizer.gradient.visbias .= vec(mean(v, 1))
   optimizer.gradient.visbias .-= vec(mean(vmodel, 1))

   optimizer.gradient.hidbias .= vec(mean(h, 1))
   optimizer.gradient.hidbias .-= vec(mean(hmodel, 1))
   optimizer.gradient
end

function computegradient!(
      optimizer::LoglikelihoodOptimizer{GaussianBernoulliRBM},
      v::M, vmodel::M, h::M, hmodel::M, gbrbm::GaussianBernoulliRBM
      ) where {M<: AbstractArray{Float64, 2}}

   # See bottom of page 15 in [Krizhevsky, 2009].

   if optimizer.sdlearningrate > 0.0
      optimizer.gradient.sd .=
            sdupdateterm(gbrbm, v, h) - sdupdateterm(gbrbm, vmodel, hmodel)
   end

   v ./= gbrbm.sd'
   vmodel ./= gbrbm.sd'

   At_mul_B!(optimizer.gradient.weights, v, h)
   At_mul_B!(optimizer.negupdate, vmodel, hmodel)
   optimizer.gradient.weights .-= optimizer.negupdate

   optimizer.gradient.hidbias .= vec(mean(h, 1) - mean(hmodel, 1))
   optimizer.gradient.visbias .= vec(mean(v, 1) - mean(vmodel, 1)) ./ gbrbm.sd

   optimizer.gradient
end

function computegradient!(
      optimizer::AbstractLoglikelihoodOptimizer{GaussianBernoulliRBM2},
      v::M, vmodel::M, h::M, hmodel::M, gbrbm::GaussianBernoulliRBM2
      ) where {M<: AbstractArray{Float64, 2}}

   # See Cho,
   # "Improved learning of Gaussian-Bernoulli restricted Boltzmann machines"
   sdsq = gbrbm.sd .^ 2

   if optimizer.sdlearningrate > 0.0
      sdgrads = vmodel .* (hmodel * gbrbm.weights')
      sdgrads .-= v .* (h * gbrbm.weights')
      sdgrads .*= 2.0
      sdgrads .+= (v .- gbrbm.visbias') .^ 2
      sdgrads .-= (vmodel .- gbrbm.visbias') .^ 2
      optimizer.gradient.sd .= vec(mean(sdgrads, 1))
      optimizer.gradient.sd ./= sdsq
      optimizer.gradient.sd ./= gbrbm.sd
   end

   v ./= sdsq'
   vmodel ./= sdsq'

   At_mul_B!(optimizer.gradient.weights, v, h)
   At_mul_B!(optimizer.negupdate, vmodel, hmodel)
   optimizer.gradient.weights .-= optimizer.negupdate

   optimizer.gradient.hidbias .= vec(mean(h, 1) - mean(hmodel, 1))
   optimizer.gradient.visbias .= vec(mean(v, 1) - mean(vmodel, 1))

   optimizer.gradient
end

function computegradient!(
      optimizer::BeamAdversarialOptimizer{R},
      v::M, vmodel::M, h::M, hmodel::M, rbm::AbstractRBM
      ) where {M<: AbstractArray{Float64, 2}, R <:AbstractRBM}

   optimizer.critic = nearestneighbourcritic(h, hmodel, optimizer.knearest)

   nvisible = nvisiblenodes(rbm)
   nhidden = nhiddennodes(rbm)

   for i = 1:nvisible
      for j = 1:nhidden
         optimizer.gradient.weights[i, j] =
               cov(optimizer.critic, vmodel[:, i] .* hmodel[:, j])
      end
   end

   # TODO check if standard deviation needed
   for i = 1:nvisible
      optimizer.gradient.visbias[i] = cov(optimizer.critic, vmodel[:, i])
   end

   for j = 1:nhidden
      optimizer.gradient.hidbias[j] = cov(optimizer.critic, hmodel[:, j])
   end

   optimizer.gradient
end

function computegradient!(
      optimizer::BeamAdversarialOptimizer{GaussianBernoulliRBM2},
      v::M, vmodel::M, h::M, hmodel::M, rbm::GaussianBernoulliRBM2
      ) where {M<: AbstractArray{Float64, 2}}

   invoke(computegradient!,
         Tuple{BeamAdversarialOptimizer{GaussianBernoulliRBM2}, M, M, M, M, AbstractRBM},
         optimizer, v, vmodel, h, hmodel, rbm)

   sdsq = rbm.sd .^ 2

   weights = optimizer.gradient.weights
   visbias = optimizer.gradient.visbias
   nvisible = size(weights, 1)

   weights ./= sdsq
   visbias ./= sdsq

   if optimizer.sdlearningrate > 0
      for i = 1:nvisible
         optimizer.gradient.sd[i] =
               cov(optimizer.critic, (vmodel[:, i] - visbias[i]) .^ 2 -
                     2 * vmodel[:, i] .* (hmodel * weights[i, :]))
      end
   end

   optimizer.gradient
end

function computegradient!(optimizer::CombinedOptimizer{R},
      v::M, vmodel::M, h::M, hmodel::M, rbm::AbstractRBM
      ) where {M<: AbstractArray{Float64, 2}, R <:AbstractRBM}

   computegradient!(optimizer.part1, copy(v), copy(vmodel), copy(h), hmodel, rbm)
   computegradient!(optimizer.part2, v, vmodel, h, hmodel, rbm)

   grad1 = optimizer.part1.gradient
   grad2 = optimizer.part2.gradient

   optimizer.gradient.weights .=
         grad1.weights * optimizer.weight1 +
         grad2.weights * (1 - optimizer.weight1)

   optimizer.gradient.visbias .=
         grad1.visbias * optimizer.weight1 +
         grad2.visbias * (1 - optimizer.weight1)

   optimizer.gradient.hidbias .=
         grad1.hidbias * optimizer.weight1 +
         grad2.hidbias * (1 - optimizer.weight1)

   optimizer.gradient
end

function computegradient!(optimizer::CombinedOptimizer{R},
      v::M, vmodel::M, h::M, hmodel::M, rbm::R
      ) where {M<: AbstractArray{Float64, 2},
            R <:Union{GaussianBernoulliRBM, GaussianBernoulliRBM2}}

   invoke(computegradient!,
         Tuple{CombinedOptimizer{R}, M, M, M, M, AbstractRBM},
         optimizer, v, vmodel, h, hmodel, rbm)

   optimizer.gradient.sd .=
         optimizer.part1.gradient.sd .* optimizer.weight1 .+
         optimizer.part2.gradient.sd .* (1 - optimizer.weight1)

   optimizer.gradient
end


"""
    updateparameters!(rbm, optimizer)
Updates the RBM by walking a step in the direction of the gradient that
has been computed by calling `computegradient!` on `optimizer`.
"""
function updateparameters!(rbm::AbstractRBM,
      optimizer::AbstractOptimizer{R}) where {R <: AbstractRBM}

   updateweightsandbiases!(rbm, optimizer)
end

function updateparameters!(rbm::Binomial2BernoulliRBM,
      optimizer::AbstractOptimizer{Binomial2BernoulliRBM})

   # To train a Binomial2BernoulliRBM exactly like
   # training a BernoulliRBM where each two nodes share the weights,
   # use half the learning rate in the visible nodes.
   learningratehidden = optimizer.learningrate
   learningrate = optimizer.learningrate / 2.0

   optimizer.gradient.weights .*= learningrate
   optimizer.gradient.visbias .*= learningrate
   optimizer.gradient.hidbias .*= learningratehidden
   rbm.weights .+= optimizer.gradient.weights
   rbm.visbias .+= optimizer.gradient.visbias
   rbm.hidbias .+= optimizer.gradient.hidbias
   rbm
end

function updateparameters!(rbm::R, optimizer::AbstractOptimizer{R}
      ) where {R <: Union{GaussianBernoulliRBM, GaussianBernoulliRBM2}}

   updateweightsandbiases!(rbm, optimizer)

   if optimizer.sdlearningrate > 0.0
      optimizer.gradient.sd .*= optimizer.sdlearningrate
      rbm.sd .+= optimizer.gradient.sd
   end
   rbm
end


function updateweightsandbiases!(rbm::R,
      optimizer::AbstractOptimizer{R}) where {R <: AbstractRBM}

   optimizer.gradient.weights .*= optimizer.learningrate
   optimizer.gradient.visbias .*= optimizer.learningrate
   optimizer.gradient.hidbias .*= optimizer.learningrate
   rbm.weights .+= optimizer.gradient.weights
   rbm.visbias .+= optimizer.gradient.visbias
   rbm.hidbias .+= optimizer.gradient.hidbias
   rbm
end

