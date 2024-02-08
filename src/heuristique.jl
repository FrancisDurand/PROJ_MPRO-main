inf = 99999999999
using CPLEX
using JuMP

function heuristique_statique(n, s, t, S, p, d)
    start = time() # Démarrer un chronomètre

    # Initialisation des vecteurs qui seront utilisés
    visited = falses(n)
    accumulated_duration = inf * ones(Float64, n)
    accumulated_weight = zeros(Int, n)
    predecessors = zeros(Int, n)

    accumulated_duration[s] = 0
    accumulated_weight[s] = p[s]

    for _ in 1:n
        # Trouver le sommet non visité avec la plus petite duration actuelle
        u = argmin(accumulated_duration .+ visited .* inf)
        
        visited[u] = true

        # Si le sommet trouvé est la destination, arrêtez la boucle
        if u == t
            break
        end

        # Mise à jour les durations, poids et les prédécesseurs des voisins de u
        for v in 1:n
            # Si non visité
            if !visited[v]
                # Si :
                # 1. la nouvelle duration est inférieure à la duration actuelle et le nouveau poids ne dépassera pas S
                # ou
                # 2. la nouvelle duration est égale à la duration actuelle, mais le nouveau poids est inférieur à celui actuel
                if (d[u, v] + accumulated_duration[u])<accumulated_duration[v] && (p[v]+accumulated_weight[u])<= S || (d[u, v] + accumulated_duration[u])==accumulated_duration[v] && (p[v]+accumulated_weight[u])<accumulated_weight[v]
                    accumulated_duration[v] = d[u, v] + accumulated_duration[u]
                    predecessors[v] = u
                    accumulated_weight[v] = p[v] + accumulated_weight[u] 
                end
            end
        end
    end

    # Reconstruction du chemin si trouvé
    if predecessors[t] != 0
        path = [t]
        u = t
        while u != s
            u = predecessors[u]
            pushfirst!(path, u)
        end

    # Si non trouvé, minimiser le poids
    else
        print("non optimal")

        # Initialisation des vecteurs qui seront utilisés
        visited = falses(n)
        accumulated_duration = inf * ones(Float64, n)
        accumulated_weight = inf * ones(Float64, n)
        predecessors = zeros(Int, n)

        accumulated_duration[s] = 0
        accumulated_weight[s] = p[s]

        for _ in 1:n
            # Trouver le sommet non visité avec le plus petit poids actuel
            u = argmin(accumulated_weight .+ visited .* inf )
            
            visited[u] = true

            # Si le sommet trouvé est la destination, arrêtez la boucle
            if u == t
                break
            end

            # Mise à jour les durations, poids et les prédécesseurs des voisins de u
            for v in 1:n
                # Si non visité et l'arc (u,v) existe
                if !visited[v] && d[u,v]!= inf
                    # Si :
                    # 1. le nouveau poids est inférieur à l'actuel
                    # ou
                    # 2. si le nouveau poids est égal à l'actuel mais que la duration est plus petite
                    if (p[v]+accumulated_weight[u])<accumulated_weight[v] || (p[v]+accumulated_weight[u])<=accumulated_weight[v] && (d[u, v] + accumulated_duration[u])<accumulated_duration[v]
                        accumulated_duration[v] = d[u, v] + accumulated_duration[u]
                        predecessors[v] = u
                        accumulated_weight[v] = p[v] + accumulated_weight[u] 
                    end
                end
            end
        end

        # si le chemin n'est pas trouvé ou si nous dépassons le poids, aucune solution respectant le poids maximum
        if predecessors[t] == 0 || accumulated_weight[t] > S
            return false, [], [] , time()-start
        end

        # Reconstruction du chemin
        path = [t]
        u = t
        while u != s
            u = predecessors[u]
            pushfirst!(path, u)
        end
        
    end

    return true, path, accumulated_duration[t], time() - start
end

"""

Constat 1 : Les valeurs de S sont beaucoup plus grandes que d2 (d2 est de l'ordre de 1% de S)

Constat 2 : Les D_ij sont grand devant d1 dans un bon nombre de cas -> ça laisse penser qu'avoir un
chemin résistant à une unique "attaque" sur l'un des arc va dans un bon nombre de cas être une bonne solution,
a condition bien sur que ce chemin ne soit pas beaucoup trop long

Idée de l'heuristique pour le problème robuste : 
De ces deux constats vient une heuristique : Résoudre le problème robuste avec le budjet S-d2 à la place de S.
On construit ainsi un chemin acceptable (bien souvent, j'ai l'impression que S-d2 reste grand en comparaison des poids des chemins construits)
Il reste rendre ce chemin moins vulnérable aux attaques sur un arc, pour ce faire, on va simplement 
enlever l'arc qui est la plus vulnérable à une attaque, et appeler recursivement ce qui précède jusqu'à 
ce que s et t soient déconnéctés, on renvoie alors le meilleur des chemins qu'on a considéré

"""

function chemin_vulnerable(n, s, t, S, d2, p, d)
    exist_path, path, _, _ = heuristique_statique(n, s, t, S-d2, p, d)
    if !exist_path
        return false, [] #si on a trouvé un chemin et le chemin en question
    else
        return true, path
    end
end


function heuristique(n, s, t, S, d1, d2, p, ph, d, D)
    start = time()
    _, path = chemin_vulnerable(n, s, t, S, d2, p, d)
    best_path = path

    #calcul de la valeur du chemin pour le vrai problème robuste

    #recuperation de la valeur des arcs
    arcs = []
    cout_arcs = []
    var_cout_arc = []
    for i in 1::(length(path)-1)
        arcs.append((path[i],path[i+1]))
        cout_arcs.append(d[path[i],path[i+1]])
        var_cout_arc.append(D[path[i],path[i+1]])
    end



    #Calcul du vrai poids de notre chemin
    model = JuMP.Model(CPLEX.Optimizer)
    @variable(model, 0 <= delta1[1:length(arcs)])
    for i in 1::length(arcs)
        @constraint(model,delta1[i] <= D[path[i],path[i+1]])
    end
    @constraint(model,sum(delta1[i] for i in 1:length(arcs)) <= d1)
    @objective(esclave_1, Max, sum(cout_arcs[i] for i in 1:length(arcs)) + sum(cout_arcs[i]delta1[i] for i in 1:length(arcs)))
    optimize!(model)
    vrai_cout_path = objective_value(model)

    best_path_cout = vrai_cout_path

    #calcul de l'arête qui doit être éjectée
    pire_arc = 1
    cout_pire_arc = min(d1,var_cout_arc[1])*cout_arcs[1]
    for i in range 1:length(arcs)
        if cout_pire_arc >= min(d1,var_cout_arc[i])*cout_arcs[i]
            pire_arc = i
            cout_pire_arc = min(d1,var_cout_arc[i])*cout_arcs[i]
        end
    end

    while vrai_cout_path < inf

        #retirer le pire arc du graphe
        d[path[i],path[i+1]] = inf

        #recalcul des quantités

        _, path = chemin_vulnerable(n, s, t, S, d2, p, d)

        #calcul de la valeur du chemin pour le vrai problème robuste

        #recuperation de la valeur des arcs
        arcs = []
        cout_arcs = []
        var_cout_arc = []
        for i in 1::(length(path)-1)
            arcs.append((path[i],path[i+1]))
            cout_arcs.append(d[path[i],path[i+1]])
            var_cout_arc.append(D[path[i],path[i+1]])
        end

        #Calcul du vrai poids de notre chemin
        model = JuMP.Model(CPLEX.Optimizer)
        @variable(model, 0 <= delta1[1:length(arcs)])
        for i in 1::length(arcs)
            @constraint(model,delta1[i] <= D[path[i],path[i+1]])
        end
        @constraint(model,sum(delta1[i] for i in 1:length(arcs)) <= d1)
        @objective(esclave_1, Max, sum(cout_arcs[i] for i in 1:length(arcs)) + sum(cout_arcs[i]delta1[i] for i in 1:length(arcs)))
        optimize!(model)
        vrai_cout_path = objective_value(model)

        if best_path_cout >= vrai_cout_path
            best_path_cout = vrai_cout_path
            best_path = path
        end

        
        #calcul de l'arête qui doit être éjectée
        pire_arc = 1
        cout_pire_arc = min(d1,var_cout_arc[1])*cout_arcs[1]
        for i in range 1:length(arcs)
            if cout_pire_arc >= min(d1,var_cout_arc[i])*cout_arcs[i]
                pire_arc = i
                cout_pire_arc = min(d1,var_cout_arc[i])*cout_arcs[i]
            end
        end
            
    end

    return true, best_path, best_path_cout, time()-start #attantion, on renvoie le path et non x
end

