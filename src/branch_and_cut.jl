using CPLEX
using JuMP

"""
Résoudre instance par branch_and_cut :

Argument
- n, s, t, S, d1, d2, p, ph, d, D : donnés du problème

Return
- true si le problème est résolu de manière optimale
- x : tableau de variables bidimensionnelles tel que x[i, j] = 1 si on passe de i à j
- valeur de la fonction objectif
- temps de résolution en secondes
- nombre de coupes ajoutées
"""

function branch_and_cut(n, s, t, S, d1, d2, p, ph, d, D)

    # Démarrer un chronomètre
    start = time()

    # Définir la fonction objective et les contraintes du programme statique

    m = JuMP.Model(CPLEX.Optimizer)
    # Variables du modèle
    @variable(m, x[1:n, 1:n], Bin)
    @variable(m, y[1:n], Bin)
    @variable(m, z >= 0)

    # Contraintes
    @constraint(m, sum(x[s,j] for j in 1:n) - sum(x[j,s] for j in 1:n) == 1) # le chemin quitte s
    @constraint(m, sum(x[t,j] for j in 1:n) - sum(x[j,t] for j in 1:n) == -1) # le chemin arrive en t

    for v in 1:n
        if v != s && v != t
            @constraint(m, sum(x[i, v] for i = 1:n) == sum(x[v, j] for j = 1:n)) # conservation du flot
        end
        if v!=t
            @constraint(m, y[v] == sum(x[v,j] for j in 1:n)) # lien entre les variable x et y
        end
    end

    @constraint(m, y[t] == sum(x[i,t] for i in 1:n)) # lien entre les variables x et y_t

    # Contrainte d'objectif (c'est à dire U^1* = {dij1 = dij})
    @constraint(m, z >= sum(p[v]*y[v] for v in 1:n))

    # Contrainte de poids (c'est à dire U^2* = {pi2 = pi})
    @constraint(m, z >= sum(d[i,j]*x[i,j] for i in 1:n, j in 1:n))

    # Fonction objective
    @objective(m, Min, z)


    function my_callback_function(cb_data) #callback pour les contraintes de U^1
        lazy_called = true
        current_x = callback_value.(cb_data, x)
        current_y = callback_value.(cb_data, y)
        current_z = callback_value(cb_data, z)
        #println("Called from (x, y,z ) = ($current_x, $current_y, $current_z")
        status = callback_node_status(cb_data, m)
            #println("Solution is integer feasible!")

            # Résoudre le sous problème liéé à U^1
            esclave_1 = JuMP.Model(CPLEX.Optimizer)
            @variable(esclave_1, 0 <= delta1[1:n, 1:n])
            for i in 1:n
                for j in 1:n
                    @constraint(esclave_1, delta1[i, j] <= D[i, j])
                end
            end
            @constraint(esclave_1, sum(delta1[i,j] for i in 1:n, j in 1:n) <= d1)
            @objective(esclave_1, Max, sum(current_x[i,j]*d[i,j] for i in 1:n, j in 1:n) + sum(current_x[i,j]*d[i,j]delta1[i,j] for i in 1:n, j in 1:n)) 
            optimize!(esclave_1)

            #Ajout de la lazy constraint

            current_delta1 = value.(delta1)
            current_z1 = objective_value(esclave_1)

            if current_z1 > current_z + 1e-6
                con = @build_constraint( z >= sum(d[i,j]*x[i,j] for i in 1:n, j in 1:n) + sum(d[i,j]*current_delta1[i,j]*x[i,j] for i in 1:n, j in 1:n))
                #println("Adding $(con)")
                MOI.submit(m, MOI.LazyConstraint(cb_data), con)
            end

            # Résoudre le sous problème liéé à U^2
            esclave_2 = JuMP.Model(CPLEX.Optimizer)
            # Variables du modèle
            @variable(esclave_2, 0 <= delta2[1:n] <= 2)
            @constraint(esclave_2, sum(delta2[v] for v in 1:n) <= d1)
            @objective(esclave_2, Max, sum(current_y[v]*p[v] for v in 1:n) + sum(current_y[v]*ph[v]*delta2[v] for v in 1:n)) #Je suis pas sur que le 1 + passe pour le PL
            optimize!(esclave_2)
            current_delta2 = value.(delta2)
            current_z2 = objective_value(esclave_2)

            if current_z2 > S + 1e-6
                con = @build_constraint(sum(y[v]*p[v] for v in 1:n) + sum(y[v]*ph[v]*current_delta2[v] for v in 1:n) <= S)
                #println("Adding $(con)")
                MOI.submit(m, MOI.LazyConstraint(cb_data), con)
            end
    end
    set_attribute(m, MOI.LazyConstraintCallback(),my_callback_function)
    optimize!(m)
    return JuMP.primal_status(m) == MOI.FEASIBLE_POINT, x, JuMP.objective_value(m), time() - start
end