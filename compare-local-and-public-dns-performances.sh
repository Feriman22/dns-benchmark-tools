#!/bin/ksh

echo "=========================================="
echo "DNS Benchmark Test (Detailed)"
echo "=========================================="
echo ""

# Number of repeats
repeat="10"

# Színkódok
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# Domain list
DOMAINS=(
        "google.com"
        "facebook.com"
        "messenger.com"
        "youtube.com"
        "twitter.com"
        "amazon.com"
        "reddit.com"
        "github.com"
        "stackoverflow.com"
        "wikipedia.org"
        "netflix.com"
        "index.hu"
        "origo.hu"
        "444.hu"
        "hvg.hu"
        "telex.hu"
        "portfolio.hu"
        "telekom.hu"
        "otpbank.hu"
)

# DNS servers
typeset -A DNS_SERVERS
DNS_SERVERS["Google DNS"]="8.8.8.8"
DNS_SERVERS["Cloudflare DNS"]="1.1.1.1"
DNS_SERVERS["Local DNS"]="192.168.1.30"

test_dns() {
        dns_name=$1
        dns_server=$2

        # Cache warmup
        for domain in "${DOMAINS[@]}"; do
                dig +short +timeout=2 "$domain" @"$dns_server" > /dev/null 2>&1
        done

        sleep 0.5

        # First round
        first_total=0
        first_count=0

        for domain in "${DOMAINS[@]}"; do
                query_time=$(dig +stats "$domain" @"$dns_server" 2>/dev/null | grep "Query time:" | awk '{print $4}')

                if [ -n "$query_time" ] && [ "$query_time" != "0" ]; then
                        ((first_total=first_total + query_time))
                        ((first_count=first_count + 1))
                fi
        done

        # Second round (cache)
        cache_total=0
        cache_count=0

        i=1
        while [ $i -le $repeat ]; do
                for domain in "${DOMAINS[@]}"; do
                        query_time=$(dig +stats "$domain" @"$dns_server" 2>/dev/null | grep "Query time:" | awk '{print $4}')

                        if [ -n "$query_time" ]; then
                                ((cache_total=cache_total + query_time))
                                ((cache_count=cache_count + 1))
                        fi
                done
                ((i=i + 1))
        done

        # Third round (stabilize cache)
        cache2_total=0
        cache2_count=0

        i=1
        while [ $i -le $repeat ]; do
                for domain in "${DOMAINS[@]}"; do
                        query_time=$(dig +stats "$domain" @"$dns_server" 2>/dev/null | grep "Query time:" | awk '{print $4}')

                        if [ -n "$query_time" ]; then
                                ((cache2_total=cache2_total + query_time))
                                ((cache2_count=cache2_count + 1))
                        fi
                done
                ((i=i + 1))
        done

        # Calculate results
        first_avg="0.000"
        cache_avg="0.000"
        cache2_avg="0.000"

        if [ $first_count -gt 0 ]; then
                first_avg=$(awk "BEGIN {printf \"%.3f\", $first_total/$first_count}")
        fi

        if [ $cache_count -gt 0 ]; then
                cache_avg=$(awk "BEGIN {printf \"%.3f\", $cache_total/$cache_count}")
        fi

        if [ $cache2_count -gt 0 ]; then
                cache2_avg=$(awk "BEGIN {printf \"%.3f\", $cache2_total/$cache2_count}")
        fi

        # Print results
        echo "$dns_name|$first_avg|$cache_avg|$cache2_avg|$first_count|$cache_count|$cache2_count"
}

# Run tests
typeset -a results
total_tests=${#DNS_SERVERS[@]}
current=0

for dns_name in "${!DNS_SERVERS[@]}"; do
        ((current=current + 1))
        dns_server="${DNS_SERVERS[$dns_name]}"

        echo -e "${YELLOW}[$current/$total_tests] Testing: $dns_name ($dns_server)...${NC}" >&2

        result=$(test_dns "$dns_name" "$dns_server")
        results[${#results[@]}]="$result"
done

# Print final results
echo ""
echo "=========================================="
echo "RESULTS SUMMARY"
echo "=========================================="
echo ""

printf "${BLUE}%-20s ${GREEN}%13s %13s %13s ${YELLOW}%10s${NC}\n" \
        "DNS Server" "First (ms)" "Cache (ms)" "Cache2 (ms)" "Success"
echo "--------------------------------------------------------------------"

for result in "${results[@]}"; do
        IFS='|' read -r dns_name first cache cache2 count1 count2 count3 <<< "$result"

        cache2_float=$(echo "$cache2" | awk '{print $1+0}')

        if (( $(echo "$cache2_float < 2" | bc -l) )); then
                color=$GREEN
        elif (( $(echo "$cache2_float < 10" | bc -l) )); then
                color=$YELLOW
        else
                color=$RED
        fi

        printf "%-20s ${GREEN}%13s ${color}%13s %13s${NC} ${YELLOW}%6s/$((repeat * ${#DOMAINS[@]}))${NC}\n" \
                "$dns_name" "$first" "$cache" "$cache2" "$count3"
done

echo ""
echo "=========================================="
echo "ANALYSIS"
echo "=========================================="
echo ""

# Best cache performance
best_cache=""
best_cache_value=999999

for result in "${results[@]}"; do
        IFS='|' read -r dns_name first cache cache2 count1 count2 count3 <<< "$result"
        cache2_float=$(echo "$cache2" | awk '{print $1+0}')

        if (( $(echo "$cache2_float < $best_cache_value" | bc -l) )); then
                best_cache_value=$cache2_float
                best_cache="$dns_name"
        fi
done

echo -e "${GREEN} Fastest (cached): $best_cache ($best_cache_value ms)${NC}"

# Best first query
best_first=""
best_first_value=999999

for result in "${results[@]}"; do
        IFS='|' read -r dns_name first cache cache2 count1 count2 count3 <<< "$result"
        first_float=$(echo "$first" | awk '{print $1+0}')

        if (( $(echo "$first_float < $best_first_value" | bc -l) )); then
                best_first_value=$first_float
                best_first="$dns_name"
        fi
done

echo -e "${BLUE} Fastest (first query): $best_first ($best_first_value ms)${NC}"

echo ""
echo "Note: Lower is better. Cache2 = stabilized cache performance."
echo "=========================================="
