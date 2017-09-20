"""
    joindbms(dbms)
    joindbms(dbms, visibleindexes)
Joins the DBMs given by the vector `dbms` by joining each layer of RBMs.

If the vector `visibleindexes` is specified, it is supposed to contain in the
i'th entry an indexing vector that determines the positions in the combined
DBM for the visible nodes of the i'th of the `dbms`.
By default the indexes of the visible nodes are assumed to be consecutive.
"""
function joindbms(dbms::Vector{BasicDBM}, visibleindexes = [])
   jointdbm = BasicDBM(length(dbms[1]))
   jointdbm[1] = joinrbms([dbms[i][1] for i in eachindex(dbms)],
         visibleindexes)
   for j = 2:length(dbms[1])
      jointdbm[j] = joinrbms([dbms[i][j] for i in eachindex(dbms)])
   end
   jointdbm
end


"""
    joinrbms(rbms)
    joinrbms(rbms, visibleindexes)
Joins the given vector of `rbms` of the same type to form one RBM of this type
and returns the joined RBM.
"""
function joinrbms{T<:AbstractRBM}(rbm1::T, rbm2::T)
   joinrbms(T[rbm1, rbm2])
end

function joinrbms(rbms::Vector{BernoulliRBM}, visibleindexes = [])
   jointvisiblebias = joinvecs([rbm.visbias for rbm in rbms], visibleindexes)
   jointhiddenbias = vcat(map(rbm -> rbm.hidbias, rbms)...)
   BernoulliRBM(joinweights(rbms, visibleindexes),
         jointvisiblebias, jointhiddenbias)
end

function joinrbms(rbms::Vector{GaussianBernoulliRBM}, visibleindexes = [])
   jointvisiblebias = joinvecs([rbm.visbias for rbm in rbms], visibleindexes)
   jointhiddenbias = vcat(map(rbm -> rbm.hidbias, rbms)...)
   jointsd = joinvecs([rbm.sd for rbm in rbms], visibleindexes)
   GaussianBernoulliRBM(joinweights(rbms, visibleindexes),
         jointvisiblebias, jointhiddenbias, jointsd)
end


"""
    joinvecs(vecs, indexes)
Combines the Float-vectors in `vecs` into one vector. The `indexes`` vector must
contain in the i'th entry the indexes that the elements of the i'th vector in
`vecs` are supposed to have in the resulting combined vector.
"""
function joinvecs(vecs::Vector{Vector{Float64}}, indexes = [])
   if isempty(indexes)
      jointvec = vcat(vecs...)
   else
      jointlength = mapreduce(v -> length(v), +, 0, vecs)
      jointvec = Vector{Float64}(jointlength)
      for i in eachindex(vecs)
         jointvec[indexes[i]] = vecs[i]
      end
   end
   jointvec
end

"""
    joinweights(rbms)
    joinweights(rbms, visibleindexes)
Combines the weight matrices of the RBMs in the vector `rbms` into one weight
matrix and returns it.

If the vector `visibleindexes` is specified, it is supposed to contain in the
i'th entry an indexing vector that determines the positions in the combined
weight matrix for the visible nodes of the i'th of the `rbms`.
By default the indexes of the visible nodes are assumed to be consecutive.
"""
function joinweights{T<:AbstractRBM}(rbms::Vector{T}, visibleindexes = [])
   jointnhidden = mapreduce(rbm -> length(rbm.hidbias), +, 0, rbms)
   jointnvisible = mapreduce(rbm -> length(rbm.visbias), +, 0, rbms)
   jointweights = zeros(jointnvisible, jointnhidden)
   offset = 0

   # if visibleindexes are not provided, construct them
   if isempty(visibleindexes)
      visibleindexes = Array{UnitRange}(length(rbms))
      for i in eachindex(rbms)
         nvisible = length(rbms[i].visbias)
         visibleindexes[i] = offset + (1:nvisible)
         offset += nvisible
      end
   elseif length(visibleindexes) != length(rbms)
      error("There must be as many indexing vectors as RBMs.")
   end

   offset = 0
   for i = eachindex(rbms)
      nhidden = length(rbms[i].hidbias)
      jointweights[visibleindexes[i], offset + (1:nhidden)] = rbms[i].weights
      offset += nhidden
   end

   jointweights
end
