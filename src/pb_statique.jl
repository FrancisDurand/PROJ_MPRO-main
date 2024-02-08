using CPLEX
using JuMP

"""
Résoudre instance du problème statique

Argument
- n, s, t, S, p, d : donnés du problème

Return
- true si le problème est résolu de manière optimale
- x : tableau de variables bidimensionnelles tel que x[i, j] = 1 si on passe de i à j
- valeur de la fonction objectif
- temps de résolution en secondes
"""
function pb_statique(n, s, t, S, p, d)
    # Créer le modèle
    m = JuMP.Model(CPLEX.Optimizer)
    set_optimizer_attribute(m, "CPX_PARAM_SCRIND", 0) # Remove the solver output

    # Variables du modèle
    @variable(m, x[1:n, 1:n], Bin)
    @variable(m, y[1:n], Bin)

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

    @constraint(m, sum(p[v]*y[v] for v in 1:n) <= S) # poids

    # Fonction objective
    @objective(m, Min, sum(d[i,j]*x[i,j] for i in 1:n for j in 1:n))

    # Démarrer un chronomètre
    start = time()

    # Résoudre le modèle
    optimize!(m)

    return JuMP.primal_status(m) == MOI.FEASIBLE_POINT, x, JuMP.objective_value(m), time() - start
end