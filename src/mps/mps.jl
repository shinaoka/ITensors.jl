
mutable struct MPS
  N_::Int
  A_::Vector{ITensor}
  llim_::Int
  rlim_::Int

  MPS() = new(0,Vector{ITensor}(),0,0)

  function MPS(N::Int, A::Vector{ITensor}, llim::Int, rlim::Int)
    new(N,A,llim,rlim)
  end
  
  function MPS(sites::SiteSet)
    N = length(sites)
    v = Vector{ITensor}(undef, N)
    l = [Index(1, "Link,l=$ii") for ii ∈ 1:N-1]
    for ii in 1:N
      s = sites[ii]
      if ii == 1
        v[ii] = ITensor(l[ii], s)
      elseif ii == N
        v[ii] = ITensor(l[ii-1], s)
      else
        v[ii] = ITensor(l[ii-1], l[ii], s)
      end
    end
    new(N,v,0,N+1)
  end

  function MPS(::Type{T}, is::InitState) where {T}
    N = length(is)
    its = Vector{ITensor}(undef, length(is))
    link_inds  = Vector{Index}(undef, length(is))
    for ii in 1:N
        i_is = is[ii]
        i_site = site(is, ii)
        spin_op = op(T(i_site), i_is)
        link_inds[ii] = Index(1, "Link,l=$ii")
        s = i_site 
        local this_it
        if ii == 1
            this_it = ITensor(link_inds[ii], i_site)
            this_it[link_inds[ii](1), s[:]] = spin_op[s[:]]
        elseif ii == N
            this_it = ITensor(link_inds[ii-1], i_site)
            this_it[link_inds[ii-1](1), s[:]] = spin_op[s[:]]
        else
            this_it = ITensor(link_inds[ii-1], link_inds[ii], i_site)
            this_it[link_inds[ii-1](1), link_inds[ii](1), s[:]] = spin_op[s[:]]
        end
        its[ii] = this_it
    end
    # construct InitState from SiteSet -- is(sites, "Up")
    new(N,its,0,2)
  end
end
MPS(N::Int, d::Int, opcode::String) = MPS(InitState(Sites(N,d), opcode))
MPS(N::Int) = MPS(N,Vector{ITensor}(undef,N),0,N+1)
MPS(s::SiteSet, opcode::String) = MPS(InitState(s, opcode))

length(m::MPS) = m.N_
leftLim(m::MPS) = m.llim_
rightLim(m::MPS) = m.rlim_

getindex(m::MPS, n::Integer) = getindex(m.A_,n)
setindex!(m::MPS,T::ITensor,n::Integer) = setindex!(m.A_,T,n)

copy(m::MPS) = MPS(m.N_,copy(m.A_),m.llim_,m.rlim_)

function dag(m::MPS)
  N = length(m)
  mdag = MPS(N)
  for i ∈ 1:N
    mdag[i] = dag(m[i])
  end
  return mdag
end

function show(io::IO,
              M::MPS)
  print(io,"MPS")
  (length(M) > 0) && print(io,"\n")
  for i=1:length(M)
    println(io,"$i  $(M[i])")
  end
end

function linkindex(M::MPS,j::Integer) 
  N = length(M)
  j ≥ length(M) && error("No link index to the right of site $j (length of MPS is $N)")
  li = commonindex(M[j],M[j+1])
  if isdefault(li)
    error("linkindex: no MPS link index at link $j")
  end
  return li
end

function siteindex(M::MPS,j::Integer)
  N = length(M)
  if j == 1
    si = uniqueindex(M[j],M[j+1])
  elseif j == N
    si = uniqueindex(M[j],M[j-1])
  else
    si = uniqueindex(M[j],M[j-1],M[j+1])
  end
  return si
end

function simlinks!(M::MPS)
  N = length(M)
  for i ∈ 1:N-1
    l = linkindex(M,i)
    l̃ = sim(l)
    M[i] *= δ(l,l̃)
    M[i+1] *= δ(l,l̃)
  end
end

function position!(M::MPS,
                   j::Integer)
  N = length(M)

  while leftLim(M) < (j-1)
    ll = leftLim(M)+1
    s = findindex(M[ll],"Site")
    if ll == 1
      (Q,R) = qr(M[ll],s)
    else
      li = linkindex(M,ll-1)
      (Q,R) = qr(M[ll],s,li)
    end
    M[ll] = Q
    M[ll+1] *= R
    M.llim_ += 1
  end

  while rightLim(M) > (j+1)
    rl = rightLim(M)-1
    s = findindex(M[rl],"Site")
    if rl == N
      (Q,R) = qr(M[rl],s)
    else
      ri = linkindex(M,rl)
      (Q,R) = qr(M[rl],s,ri)
    end
    M[rl] = Q
    M[rl-1] *= R
    M.rlim_ -= 1
  end
  M.llim_ = j-1
  M.rlim_ = j+1
end

function inner(M1::MPS,
               M2::MPS)::Number
  N = length(M1)
  if length(M2) != N
    error("inner: mismatched lengths $N and $(length(M2))")
  end
  M1dag = dag(M1)
  simlinks!(M1dag)
  O = M1dag[1]*M2[1]
  for j=2:N
    O *= M1dag[j]*M2[j]
  end
  return O[]
end

function randomMPS(sites::SiteSet,
                   m::Int=1)
  M = MPS(sites)
  for i=1:length(M)
    randn!(M[i])
    M[i] /= norm(M[i])
  end
  if m > 1
    error("randomMPS: currently only m==1 supported")
  end
  return M
end

function replaceBond!(M::MPS,
                      b::Int,
                      phi::ITensor,
                      dir::String;
                      kwargs...)
  U,S,V,u,v = svd(phi,inds(M[b]);kwargs...)
  if dir=="Fromleft"
    M[b]   = U
    M[b+1] = S*V
  elseif dir=="Fromright"
    M[b]   = U*S
    M[b+1] = V
  end
end

function maxDim(M::MPS)
  md = 1
  for b=1:length(M)-1
    md = max(md,dim(linkindex(M,b)))
  end
  return md
end
