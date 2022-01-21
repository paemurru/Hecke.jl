@doc Markdown.doc"""
    rref(M::SMat{T}; truncate = false) where {T <: FieldElement} -> (Int, SMat{T})

Return a tuple $(r, A)$ consisting of the rank $r$ of $M$ and a reduced row echelon
form $A$ of $M$.
If the function is called with `truncate = true`, the result will not contain zero
rows, so `nrows(A) == rank(M)`.
"""
rref(A::SMat{T}; truncate::Bool = false) where {T <: FieldElement} = rref!(deepcopy(A), truncate = truncate)

# This does not really work in place, but it certainly changes A
function rref!(A::SMat{T}; truncate::Bool = false) where {T <: FieldElement}
  B = sparse_matrix(base_ring(A))
  B.c = A.c
  number_of_rows = A.r

  # Remove empty rows, so they don't get into the way when we sort
  i = 1
  while i <= length(A.rows)
    if iszero(A.rows[i])
      deleteat!(A.rows, i)
    else
      i += 1
    end
  end

  # Prefer sparse rows and, if the number of non-zero entries is equal, rows
  # with more zeros in front. (Appears to be a good heuristic in practice.)
  rows = sort!(A.rows, lt = (x, y) -> length(x) < length(y) || (length(x) == length(y) && x.pos[1] > y.pos[1]))

  for r in rows
    b = _add_row_to_rref!(B, r)
    if nrows(B) == ncols(B)
      break
    end
  end

  A.nnz = B.nnz
  A.rows = B.rows
  rankA = B.r
  if !truncate
    while length(A.rows) < number_of_rows
      push!(A.rows, sparse_row(base_ring(A)))
    end
  else
    A.r = B.r
  end
  return rankA, A
end

function insert_row!(A::SMat{T}, i::Int, r::SRow{T}) where T
  insert!(A.rows, i, r)
  A.r += 1
  A.nnz += length(r)
  A.c = max(A.c, r.pos[end])
  return A
end

# Reduce v by M and if the result is not zero add it as a row (and then reduce
# M to maintain the rref).
# Return true iff v is not in the span of the rows of M.
# M is supposed to be in rref and both M and v are changed in place.
function _add_row_to_rref!(M::SMat{T}, v::SRow{T}) where { T <: FieldElem }
  if iszero(v)
    return false
  end

  pivot_found = false
  s = one(base_ring(M))
  i = 1
  new_row = 1
  while i <= length(v)
    c = v.pos[i]
    r = find_row_starting_with(M, c)
    if r > nrows(M) || M.rows[r].pos[1] > c
      # We found an entry in a column of v, where no other row of M has the pivot.
      @assert !iszero(v.values[i])
      i += 1
      if pivot_found
        # We already found a pivot
        continue
      end

      @assert i == 2 # after incrementing
      pivot_found = true
      new_row = r
      continue
    end

    # Reduce the entries of v by M.rows[r]
    t = -v.values[i] # we assume M.rows[r].pos[1] == 1 (it is the pivot)
    v = add_scaled_row!(M.rows[r], v, t)
    # Don't increase i, we deleted the entry
  end
  if !pivot_found
    return false
  end

  # Multiply v by inv(v.values[1])
  t = inv(v.values[1])
  for j = 2:length(v)
    v.values[j] = mul!(v.values[j], v.values[j], t)
  end
  v.values[1] = one(base_ring(M))
  insert_row!(M, new_row, v)

  # Reduce the rows above the newly inserted one
  for i = 1:new_row - 1
    c = M.rows[new_row].pos[1]
    j = searchsortedfirst(M.rows[i].pos, c)
    if j > length(M.rows[i].pos) || M.rows[i].pos[j] != c
      continue
    end

    t = -M.rows[i].values[j]
    l = length(M.rows[i])
    M.rows[i] = add_scaled_row!(M.rows[new_row], M.rows[i], t)
    if length(M.rows[i]) != l
      M.nnz += length(M.rows[i]) - l
    end
  end
  return true
end

###############################################################################
#
#   Kernel
#
###############################################################################

@doc Markdown.doc"""
    nullspace(M::SMat{T}) where {T <: FieldElement}

Return a tuple $(\nu, V)$ consisting of the nullity $\nu$ of $M$ and
a basis $V$ (consisting of sparse rows) for the right nullspace of $M$,
i.e. such that $Mv$ is zero for every $v$ in $V$.
"""
function nullspace(M::SMat{T}) where {T <: FieldElement}
  m = nrows(M)
  n = ncols(M)
  rank, A = rref(M)
  nullity = n - rank
  K = base_ring(M)
  X = Vector{SRow{T}}()
  if rank == 0
    for i = 1:nullity
      R = sparse_row(K)
      push!(R.pos, i)
      push!(R.values, one(K))
      push!(X, R)
    end
  elseif nullity != 0
    r = 1
    for c = 1:ncols(A)
      if r <= rank && A.rows[r].pos[1] == c
        r += 1
        continue
      end

      R = sparse_row(K)
      for i = 1:r - 1
        j = searchsortedfirst(A.rows[i].pos, c)
        if j > length(A.rows[i].pos) || A.rows[i].pos[j] != c
          continue
        end
        push!(R.pos, A.rows[i].pos[1])
        push!(R.values, -A.rows[i].values[j])
      end
      push!(R.pos, c)
      push!(R.values, one(K))
      push!(X, R)
    end
  end
  return nullity, X
end

@doc Markdown.doc"""
    right_kernel(M::SMat{T}) where {T <: FieldElement}

Return a tuple $n, V$ where $V$ is a Vector of sparse rows forming a basis of
the kernel of $M$ and $n$ is the rank of the kernel.
"""
function right_kernel(M::SMat{T}) where T <: FieldElement
   return nullspace(M)
end
